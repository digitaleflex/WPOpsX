# Déploiement d'un site WordPress

`deploy.sh` installe un site complet (MariaDB, Redis, WordPress, TLS, sauvegardes, mises à jour) sur une
infrastructure WPOpsX déjà initialisée.

## Prérequis

- Avoir lancé une fois `../../scripts/init.sh` puis démarré `traefik/`
- Docker avec `docker compose` v2
- Un domaine dont le DNS pointe vers ce serveur
- Les ports 80 et 443 ouverts

## Sommaire

- [Utilisation](#utilisation)
- [Ce que fait le script](#ce-que-fait-le-script)
- [Structure du déploiement](#structure-du-déploiement)
- [Exploitation courante](#exploitation-courante)
- [Restauration](#restauration)
- [Dépannage](#dépannage)

## Utilisation

```bash
./deploy.sh <nom_du_site> <domaine>
```

| Option | Effet |
|---|---|
| `-m, --mysql VERSION` | version de MariaDB (défaut : 10.11) |
| `-r, --redis VERSION` | version de Redis (défaut : 7-alpine) |
| `-i, --wp-image IMAGE` | image WordPress (défaut : `eflexcloud/wordpress-custom`) |
| `--clean` | **supprime les volumes existants** du site (données perdues) |
| `-y, --yes` | ne pas demander confirmation pour `--clean` |
| `--no-cron` | ne pas installer les tâches planifiées |
| `--lite` | accepté pour compatibilité (un site n'installe jamais monitoring/portainer) |
| `-h, --help` | afficher l'aide |

Exemples :

```bash
./deploy.sh blog blog.exemple.com
./deploy.sh boutique www.boutique.exemple.com -m 11.4
./deploy.sh --clean --yes test test.exemple.com     # repartir de zéro
```

## Ce que fait le script

1. Vérifie Docker, le plugin `compose` v2 et le réseau `proxy` (sinon il indique de lancer `init.sh`)
2. Valide le domaine et l'espace disque
3. Crée `wordpress/<site>/` et écrit un `.env` contenant des mots de passe aléatoires (`openssl rand -hex 32`),
   en mode **600**
4. Copie `docker-compose.yml`, `backup.sh` et `update.sh`, puis valide la configuration (`docker compose config -q`)
5. Démarre les services et attend que la base soit réellement prête (`healthcheck.sh`)
6. Contrôle la réponse HTTPS et signale les points à vérifier si elle échoue
7. Installe deux tâches cron, identifiées par le commentaire `# wpopsx:<site>` :
   - sauvegarde quotidienne à 02h00
   - mises à jour WordPress le dimanche à 03h00

> Relancer le script sans `--clean` est **sans danger** : les données existantes et les mots de passe sont
> conservés et seuls les fichiers de configuration sont réécrits.

## Structure du déploiement

```
wordpress/<site>/
├── .env                # secrets du site (mode 600, jamais versionné)
├── docker-compose.yml  # copie conforme du template
├── backup.sh           # sauvegarde base + fichiers
├── update.sh           # mises à jour WordPress
└── backups/            # sauvegardes horodatées (rotation 7 jours)
```

### Services

| Service | Rôle | Réseau | Exposition |
|---|---|---|---|
| `wordpress` | application (Apache + PHP) | `internal` + `proxy` | `https://<domaine>` via Traefik |
| `wordpress-init` | initialise les permissions de `wp-content` (uid 33) | `internal` | aucun |
| `mysql` | MariaDB | `internal` | **aucune** (hors de portée du proxy) |
| `redis` | cache objet | `internal` | **aucune** |

### Volumes et isolation

Les noms de services sont volontairement fixes : Compose n'interpole pas les **clés** YAML. L'isolation
entre sites est assurée par le nom de projet (`name: ${SITE_NAME}` en tête du compose), qui préfixe tous
les volumes et conteneurs :

```
<site>_wordpress_data   # /var/www/html (cœur, extensions, thèmes, uploads)
<site>_db_data          # /var/lib/mysql
<site>_redis_data       # /data
```

## Exploitation courante

```bash
cd wordpress/<site>

docker compose ps                      # état des services
docker compose logs -f wordpress       # journaux de l'application
docker compose logs mysql              # journaux de la base
docker compose down                    # arrêter (données conservées)
docker compose up -d                   # redémarrer
docker compose pull && docker compose up -d   # mettre à jour les images

./backup.sh                            # sauvegarde manuelle
./update.sh                            # mises à jour WP / extensions / thèmes / traductions
```

Modifier un mot de passe de base : éditer `.env` puis `docker compose up -d` (les volumes sont conservés ;
si l'utilisateur MariaDB existe déjà, son mot de passe en base doit être changé en parallèle).

## Restauration

```bash
cd wordpress/<site>
RESTORE=backups/20260916_020001        # dossier à restaurer

# 1. Base de données
gunzip -c "${RESTORE}/db.sql.gz" | docker compose exec -T mysql \
    sh -c 'exec mysql -u root "$MYSQL_DATABASE"'

# 2. Fichiers (lecture sur l'entrée standard : aucun chemin de l'hôte n'est monté)
docker compose exec -T wordpress sh -c 'tar xzf - -C /var/www/html' \
    < "${RESTORE}/files.tar.gz"

# 3. Redémarrer pour repartir sur un état propre
docker compose up -d --force-recreate
```

Chaque sauvegarde est vérifiée : la sauvegarde de la base doit se terminer par la ligne `Dump completed`
de `mysqldump`, et l'archive de fichiers est testée par `tar tzf`. Un dump tronqué est supprimé et le
script sort en erreur, pour éviter de conserver une sauvegarde inutilisable.

## Dépannage

### Le script s'arrête : « Docker n'est pas installé »
Docker doit être installé et le démon démarré (`docker info` doit répondre).

### « le plugin 'docker compose' (v2) est requis »
Utiliser la commande `docker compose` (avec un espace). `docker-compose` v1 n'est plus maintenu depuis
2023 et n'est plus installé par défaut sur les distributions récentes.

### « le réseau Docker 'proxy' n'existe pas »
```bash
cd ../.. && ./scripts/init.sh
```

### Le domaine est refusé comme invalide
Le format attendu est `domaine.tld` (au moins un point et un TLD de 2 caractères ou plus).

### Le site répond 502
- Vérifier que le label `traefik.docker.network=proxy` est présent (il l'est par défaut).
- `docker compose logs wordpress` et `docker logs traefik`.

### Les uploads ou l'installation d'extensions échouent
Les permissions de `wp-content` doivent appartenir à `www-data` (uid 33) :
```bash
docker compose up -d --force-recreate wordpress-init
docker compose logs wordpress-init
```

### Les certificats SSL ne sont pas générés
- `traefik/acme.json` doit exister en mode 600 (voir `traefik/README.md`).
- Le DNS doit pointer vers le serveur et le port 80 être joignable.

### Les tâches cron ne s'exécutent pas
```bash
crontab -l | grep wpopsx
cd wordpress/<site> && ./backup.sh          # exécuter à la main pour voir l'erreur
```

## Licence

MIT — voir [LICENSE](../../LICENSE).
