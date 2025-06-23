# 🚀 Quickstart – WPOpsX Lite

Ce guide vous permet de déployer un site WordPress (ou Laravel) en mode Lite sur un VPS à faibles ressources (1 vCPU, 1 Go RAM) en quelques minutes.

---

## Prérequis
- Un VPS Linux (Ubuntu/Debian recommandé)
- Docker & Docker Compose installés
- Accès root/sudo
- Un nom de domaine pointant vers votre VPS

---

## Déploiement en mode Lite

1. Clonez le dépôt WPOpsX :
   ```bash
   git clone https://github.com/digitaleflex/wpopsx.git
   cd wpopsx/wordpress/template
   ```
2. Lancez le déploiement Lite :
   ```bash
   ./deploy.sh monsite monsite.com --lite
   ```
3. Suivez les instructions à l’écran (création des volumes, configuration, etc.)

---

## Points clés du mode Lite
- Seuls les services essentiels sont installés (WordPress, Traefik, MariaDB)
- Monitoring, Portainer, Jaeger sont désactivés
- Consommation RAM/CPU minimale
- Backups et cron adaptés aux petits serveurs

---

## Accéder à votre site
- Site WordPress : https://monsite.com
- Traefik Dashboard : https://traefik.monsite.com

---

> Pour toute question ou problème, ouvrez une issue sur GitHub ou consultez la FAQ dans ce dossier. 