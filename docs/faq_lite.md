# ❓ FAQ – WPOpsX Lite

## Quels sont les prérequis pour la version Lite ?
- Un VPS Linux (1 vCPU, 1 Go RAM minimum)
- Docker & Docker Compose
- Un nom de domaine configuré

## Quels services sont installés en mode Lite ?
- WordPress (ou Laravel)
- MariaDB (config allégée)
- Traefik (reverse proxy + SSL)

## Qu'est-ce qui est désactivé dans la version Lite ?
- Monitoring (Prometheus, Grafana, Jaeger)
- Portainer (UI Docker)
- Services gourmands en RAM/CPU

## Puis-je activer le monitoring plus tard ?
Oui, il suffit de relancer le déploiement en mode Full ou d'ajouter les services via Docker Compose.

## Comment optimiser encore plus mon VPS ?
- Utilisez des images Docker basées sur Alpine
- Réduisez la fréquence des backups
- Activez le cron système (désactivez WP-Cron)
- Limitez le nombre de plugins WordPress

## Est-ce sécurisé ?
- Oui, Traefik gère le SSL et les en-têtes de sécurité
- MariaDB est isolée et protégée par mot de passe
- Pensez à changer tous les mots de passe par défaut

## Comment restaurer une sauvegarde ?
- Utilisez le script `restore.sh` fourni dans le projet
- Suivez la documentation dans ce dossier

## Puis-je héberger plusieurs sites sur le même VPS Lite ?
- Oui, mais les ressources sont limitées. 2 à 3 sites max sur 1 Go RAM.
- Pour plus, passez en mode Full ou upgradez votre VPS.

## Où trouver de l'aide ?
- Ouvrez une issue sur GitHub
- Consultez la documentation dans le dossier `docs/`
- Rejoignez la communauté (Discord/Slack à venir) 