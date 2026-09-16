# Portainer — interface de gestion Docker

Interface web pour administrer les conteneurs, images, volumes, réseaux et stacks de l'hôte.

## Démarrage

```bash
../scripts/init.sh                        # réseau proxy, .env des modules
cp .env.example .env && chmod 600 .env    # domaines + identifiants (obligatoires)
docker compose up -d
```

Le `.env` est **obligatoire** : `docker compose up` refuse de démarrer sans `PORTAINER_AUTH_USER` et
`PORTAINER_AUTH_PASSWORD_HASH`. C'est volontaire — sans authentification, Portainer est une porte
d'entrée directe sur l'hôte Docker.

## Accès

`https://<DOMAIN_NAME>` (défini dans `.env`), protégé par deux niveaux :

1. **Authentification basique Traefik** (middleware `portainer-auth`) : filtre l'accès avant d'atteindre
   Portainer, y compris pendant la fenêtre d'initialisation du compte administrateur.
2. **Compte Portainer** : créé à la première connexion.

Génération du hash (bcrypt, avec les `$` doublés) :

```bash
htpasswd -nbB admin 'monmotdepasse'
# -> admin:$2y$05$xxxx   ==>  PORTAINER_AUTH_PASSWORD_HASH=$$2y$$05$$xxxx
```

> Un `$` isolé dans le `.env` est interprété par Compose comme une variable : le hash est tronqué et
> l'authentification devient impossible.

## Aucun port publié

Le port 9000 n'est pas exposé sur l'hôte : Portainer n'est joignable que via Traefik (HTTPS + auth). Pour
un accès local de secours, décommenter dans `docker-compose.yml` :

```yaml
    ports:
      - "127.0.0.1:9000:9000"   # joignable uniquement depuis le serveur (tunnel SSH)
```

## Avertissement sécurité : le socket Docker

Portainer monte `/var/run/docker.sock`. Le `:ro` n'apporte **aucune** protection : un socket UNIX monté
en lecture seule reste pleinement appelable, et l'API Docker équivaut à un accès root sur l'hôte.

Pour réduire cette surface, intercaler un proxy de socket et monter celui-ci à la place :

```yaml
  docker-socket-proxy:
    image: tecnativa/docker-socket-proxy:0.2.0
    environment:
      - CONTAINERS=1
      - IMAGES=1
      - NETWORKS=1
      - VOLUMES=1
      - POST=1
      - EXEC=0        # désactiver ce dont Portainer n'a pas besoin
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
```

puis remplacer le montage du socket par `DOCKER_HOST=tcp://docker-socket-proxy:2375` côté Portainer.

## Maintenance

```bash
docker compose pull && docker compose up -d   # mise à jour (image épinglée)
docker compose logs -f portainer

# Sauvegarde de la base Portainer
docker run --rm -v portainer_portainer_data:/source -v "$PWD/backup:/backup" \
    alpine:3.19 tar czf /backup/portainer.tar.gz -C /source .
```

## Dépannage

| Symptôme | Piste |
|---|---|
| `PORTAINER_AUTH_USER manquant` | remplir `portainer/.env` (voir `.env.example`) |
| 502 derrière Traefik | vérifier que le conteneur est sur le réseau `proxy` (`docker inspect portainer`) |
| Impossible de définir le mot de passe administrateur | la fenêtre d'initialisation a pu être consommée : `docker volume rm portainer_portainer_data` puis redémarrer |
| Authentification basique refusée | hash tronqué : vérifier les `$$` dans le `.env` |

## Licence

MIT — voir [LICENSE](../LICENSE).
