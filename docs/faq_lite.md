# FAQ — déploiement léger

## Quels sont les prérequis ?
- Un VPS Linux (1 vCPU, 1 Go de RAM suffisent pour un site)
- Docker avec le plugin `docker compose` v2
- Un nom de domaine dont le DNS pointe vers le serveur
- Les ports 80 et 443 ouverts

## Quels services sont installés pour un site ?
Uniquement l'essentiel : WordPress, MariaDB et Redis. Traefik est un service séparé, partagé par tous les
sites du serveur.

## Qu'est-ce qui n'est PAS installé ?
Prometheus, Grafana, Jaeger et Portainer. Ce sont des modules indépendants (`monitoring/`, `portainer/`)
que le script de déploiement ne touche jamais — sur un VPS à 1 Go de RAM, il vaut mieux ne pas les lancer.

## Puis-je activer le monitoring plus tard ?
Oui, à tout moment et sans toucher aux sites :
```bash
cd monitoring && cp .env.example .env && chmod 600 .env && docker compose up -d
```

## Pourquoi `docker compose` (avec un espace) et pas `docker-compose` ?
`docker-compose` v1 n'est plus maintenu depuis 2023 et n'est plus fourni par défaut. La commande actuelle
est intégrée au client Docker : `docker compose`.

## Comment optimiser encore plus mon VPS ?
- `INNODB_BUFFER_POOL_SIZE=128M` dans le `.env` du site
- Laisser monitoring et Portainer arrêtés
- Limiter le nombre d'extensions WordPress
- Conserver la rotation des sauvegardes à 7 jours (paramètre `RETENTION_DAYS`)

## Comment sauvegarder et restaurer ?
```bash
cd wordpress/<site> && ./backup.sh               # sauvegarde manuelle
```
La sauvegarde contient la base (`db.sql.gz`) et l'intégralité des fichiers (`files.tar.gz`). La procédure
de restauration est documentée en tête de `backup.sh` et dans
[`wordpress/template/README.md`](../wordpress/template/README.md).

## Où sont mes mots de passe ?
Dans le `.env` du site, en mode 600 :
```bash
cd wordpress/<site> && grep -E '^(MYSQL|REDIS)' .env
```

## Le certificat SSL n'est pas généré, que faire ?
1. `traefik/acme.json` doit exister en mode 600 (`./scripts/init.sh`) : il stocke les certificats et le
   compte ACME, et il ne doit jamais être supprimé ni régénéré
2. Le DNS du domaine doit pointer vers le serveur
3. Le port 80 doit être joignable depuis Internet (challenge HTTP-01)
4. `docker logs traefik 2>&1 | grep -i acme`
