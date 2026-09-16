# Traefik — reverse proxy et certificats SSL

Reverse proxy central de la plateforme : routage des sites, certificats Let's Encrypt, en-têtes de sécurité.

## Sommaire

- [Démarrage](#démarrage)
- [Structure](#structure)
- [Configuration](#configuration)
- [Certificats SSL](#certificats-ssl)
- [Middlewares partagés](#middlewares-partagés)
- [Migration depuis une installation existante](#migration-depuis-une-installation-existante)
- [Pièges vérifiés](#pièges-vérifiés)
- [Dépannage](#dépannage)

---

## Démarrage

```bash
# 1. Prérequis communs (réseau `proxy`, traefik/acme.json, .env des modules)
../scripts/init.sh

# 2. Démarrage
docker compose up -d
docker compose logs -f traefik
```

Le fichier `traefik/acme.json` **doit exister** en mode 600 avant le premier démarrage, sinon Docker crée un
**répertoire** à cet emplacement et Traefik refuse d'émettre le moindre certificat :

```
ERR Unable to get ACME account: permissions 777 for /etc/traefik/acme.json are too open, please use 600
```

Si Docker a déjà créé un répertoire à la place du fichier :

```bash
docker compose down
rm -rf traefik/acme.json          # uniquement s'il s'agit bien d'un répertoire vide
../scripts/init.sh                # recrée le fichier en mode 600
docker compose up -d
```

## Structure

```
traefik/
├── docker-compose.yml     # le service Traefik (image épinglée, cap_drop, healthcheck)
├── traefik.yml            # configuration STATIQUE (lue au démarrage)
├── dynamic/
│   └── middlewares.yml    # configuration DYNAMIQUE (rechargée à chaud, sans coupure)
├── acme.json              # certificats + compte ACME — À PRÉSERVER, voir ci-dessous
├── .env.example           # uniquement pour activer le dashboard (optionnel)
└── update-domains.sh      # inventaire/contrôle des domaines déployés (lecture seule)
```

### `traefik/acme.json` — le fichier à ne jamais perdre

Il est **ignoré par Git** (il contient les clés privées des certificats) mais il est **indispensable** :
il stocke tous les certificats émis **et** le compte ACME.

- Il doit vivre à **`traefik/acme.json`**, c'est-à-dire à côté de `docker-compose.yml`, puisque celui-ci le
  monte avec `./acme.json:/etc/traefik/acme.json`.
- Il doit exister **avant le premier démarrage** et être en mode **600**.
- Il ne doit **jamais** être supprimé, régénéré ni remplacé : le perdre, c'est demander 45 nouveaux
  certificats d'un coup et se heurter aux quotas Let's Encrypt (5 certificats par semaine et par domaine).
- Sauvegarde recommandée (à inclure dans la sauvegarde du serveur) :

```bash
cp traefik/acme.json ~/acme-$(date +%F).json && chmod 600 ~/acme-$(date +%F).json
```

La séparation **statique / dynamique** n'est pas cosmétique : les deux fichiers ne se chargent pas de la
même façon et ne se rechargent pas de la même manière. Voir [Pièges vérifiés](#pièges-vérifiés).

## Configuration

### Variables (`traefik.yml` et `docker-compose.yml`)

| Élément | Où | Note |
|---|---|---|
| Email ACME | `traefik.yml`, en clair | ne peut pas venir du `.env` (voir piège n°2) |
| `certResolver` par défaut | `entryPoints.websecure` | chaque domaine routé reçoit son certificat sans rien déclarer côté site |
| Dashboard | labels `docker-compose.yml` (commentés) | désactivé par défaut |
| Middlewares partagés | `dynamic/middlewares.yml` | voir ci-dessous |

### Activer le dashboard (optionnel)

1. `cp .env.example .env && chmod 600 .env`, renseigner `DOMAIN_NAME` et un hash bcrypt.
2. Décommenter les labels `traefik.http.routers.traefik.*` dans `docker-compose.yml`.
3. `docker compose up -d`.

Générer le hash :

```bash
htpasswd -nbB admin 'monmotdepasse'
# -> admin:$2y$05$xxxx
```

> **Le `$` doit être doublé dans le `.env`** : `$$2y$$05$$xxxx`. Compose interprète un `$` seul comme le
> début d'une variable et **tronque silencieusement le hash** (`admin:$2y$05` → accès impossible).
> Vérifié : avec `$$`, le conteneur reçoit bien `admin:$2y$05$xxxx`.

## Certificats SSL

- Émission et renouvellement automatiques via le challenge **HTTP-01** (le port 80 doit être joignable).
- Les domaines sont découverts tout seuls à partir des labels Docker des sites (`providers.docker.watch`).
  Aucune réécriture de fichier n'est nécessaire pour ajouter un domaine.
- **Le wildcard exige DNS-01.** `*.exemple.com` ne peut pas être émis via HTTP-01 (voir piège n°3) : pour
  l'activer, utiliser `dnsChallenge` avec un provider DNS dans `traefik.yml`.

Contrôle de l'état des certificats :

```bash
docker exec traefik traefik healthcheck --ping     # le proxy répond
./update-domains.sh                                # domaines déclarés / certificat présent / HTTPS
docker logs traefik 2>&1 | grep -i acme            # erreurs ACME
```

## Middlewares partagés

Définis une fois dans `dynamic/middlewares.yml`, référencés par les sites avec le suffixe `@file` :

| Middleware | Usage |
|---|---|
| `security-headers@file` | interfaces d'admin : HSTS, nosniff, frame SAMEORIGIN, `X-Robots-Tag: noindex` |
| `site-security-headers@file` | sites clients : HSTS (sans `includeSubDomains`), nosniff, frame SAMEORIGIN, referrer-policy |
| `redirect-to-non-www@file` | `www.domaine.tld` → `domaine.tld` |

Volontairement **non** appliqués aux sites clients : `X-Robots-Tag: noindex` (destructeur pour le SEO) et
`Permissions-Policy` restrictive (peut casser des plugins).

## Migration depuis une installation existante

> Procédure pour un proxy **en production**. Le seul fichier à ne jamais régénérer est
> **`traefik/acme.json`** : il reste **en place**, au même chemin, puisque `docker-compose.yml` continue de
> le monter via `./acme.json:/etc/traefik/acme.json`.

```bash
cd /home/<user>/my_arch             # racine de l'installation sur le serveur

# 0. Sauvegarder TOUT, puis traefik/acme.json à part (certificats + compte ACME)
tar czf ~/traefik-backup-$(date +%F).tar.gz traefik/
cp traefik/acme.json ~/acme-$(date +%F).json && chmod 600 ~/acme-$(date +%F).json

# 1. Relever la version en place (éviter une rétrogradation)
docker exec traefik traefik version

# 2. Remplacer la configuration (JAMAIS traefik/acme.json)
#    nouveaux traefik.yml + docker-compose.yml + dossier dynamic/, à côté du acme.json existant
cd traefik
mkdir -p dynamic
ls -l acme.json                     # doit afficher -rw------- (600) et une taille non nulle

# 3. Vérifier AVANT de toucher à la production
docker compose config -q
docker compose up -d --dry-run      # (Compose v2.30+)

# 4. Appliquer
docker compose up -d
docker compose logs -f traefik
```

Si le proxy tourne depuis un `docker-compose.yml` généré par l'ancien `deploy.sh` (dossier
`/home/audest/my_arch/`), seuls `traefik.yml` et `docker-compose.yml` changent : les sites et leurs
labels restent valides, et leurs certificats déjà présents dans **`traefik/acme.json`** aussi.

**Retour arrière** : restaurer l'archive de l'étape 0 puis `docker compose up -d`.

## Pièges vérifiés

Ces comportements ont été constatés sur Traefik v3.4 (test réel, pas supposition) et expliquent la
configuration livrée :

1. **Clés inconnues en configuration statique : aucune erreur.** Une section `http:` ou `middlewares:`
   écrite dans `traefik.yml` est **ignorée silencieusement** — Traefik démarre normalement, sans le moindre
   avertissement, et vos en-têtes de sécurité n'existent pas. Toute la config dynamique doit passer par
   `providers.file` (dossier `dynamic/`) ou par les labels Docker.
2. **`${VAR}` n'est pas interpolé dans `traefik.yml`.** Traefik conserve la chaîne littérale : un
   `email: "${TRAEFIK_EMAIL}"` enregistre le compte ACME avec `${TRAEFIK_EMAIL}` comme adresse. Les valeurs
   dépendant de l'environnement doivent être écrites en clair ou passées en arguments CLI.
3. **Une section définie dans le fichier gagne sur la CLI.** Si `certificatesResolvers` existe dans
   `traefik.yml`, les arguments `--certificatesresolvers...` sont sans effet : une seule source pour un
   même bloc.
4. **Le wildcard ne fonctionne pas en HTTP-01.** Let's Encrypt n'émet `*.domaine.tld` qu'en **DNS-01**.
5. **`traefik/acme.json` en 777 → résolveur ACME désactivé** avec une erreur explicite (`please use 600`).
6. **Compose n'interpole pas les clés** : un service nommé `mysql_${SITE_NAME}:` est rejeté
   (`services additional properties 'mysql_${SITE_NAME}' not allowed`). C'est pourquoi
   `wordpress/template/docker-compose.yml` utilise des noms fixes et un `name:` de projet.

## Dépannage

| Symptôme | Piste |
|---|---|
| Aucun certificat émis | vérifier `traefik/acme.json` (`-rw-------`, taille non nulle) ; DNS du domaine → IP du serveur ; port 80 joignable ; `docker logs traefik \| grep -i acme` |
| `permissions 777 for /etc/traefik/acme.json are too open` | `chmod 600 traefik/acme.json` puis `docker compose restart traefik` |
| `traefik/acme.json` est un répertoire | Docker l'a créé faute de fichier existant : `docker compose down && rm -rf traefik/acme.json && ../scripts/init.sh` |
| `no available server` / 502 | le conteneur cible n'est pas sur le réseau `proxy`, ou Traefik choisit le mauvais réseau : ajouter le label `traefik.docker.network=proxy` |
| En-têtes de sécurité absents | le middleware est dans `traefik.yml` (ignoré, piège 1) au lieu de `dynamic/` |
| Redirection HTTP→HTTPS en boucle | vérifier qu'il ne reste pas un `redirectScheme` dans un middleware `headers` (champ retiré en v3) |
| Hash de mot de passe refusé | `$` non doublés dans le `.env` |
| Plus aucun site ne répond après migration | restaurer l'archive de l'étape 0, puis `docker compose up -d` |

## Licence

MIT — voir [LICENSE](../LICENSE).
