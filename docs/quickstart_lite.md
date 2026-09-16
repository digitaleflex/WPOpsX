# Quickstart — déployer un site WordPress

Guide court pour mettre un site WordPress en ligne sur un VPS (1 vCPU / 1 Go suffisent pour un site).

## Prérequis

- VPS Linux (Ubuntu/Debian)
- Docker avec le plugin **`docker compose` v2** (`docker compose version` doit répondre)
- Accès root ou sudo
- Un domaine dont le DNS pointe vers le VPS
- Ports **80** et **443** ouverts

## Déploiement en 4 commandes

```bash
# 1. Récupérer le dépôt
git clone https://github.com/digitaleflex/WPOpsX.git
cd WPOpsX

# 2. Préparer l'hôte (réseau proxy, traefik/acme.json en 600, .env des modules)
./scripts/init.sh

# 3. Démarrer le reverse proxy (une seule fois par serveur)
cd traefik
#    renseigner l'email Let's Encrypt dans traefik.yml
docker compose up -d
cd ..

# 4. Déployer le site
cd wordpress/template
./deploy.sh monsite monsite.com
```

À la fin, le script affiche le résumé (URL, dossier, base, identifiants) et a installé :

- une sauvegarde quotidienne à 02h00 (base + fichiers, rotation 7 jours)
- les mises à jour WordPress le dimanche à 03h00

## Ce qui n'est PAS installé

Le déploiement d'un site reste léger : **Prometheus, Grafana, Jaeger et Portainer ne sont jamais installés
par `deploy.sh`**. Ce sont des modules indépendants, à démarrer séparément et seulement si le serveur a les
ressources nécessaires :

```bash
cd monitoring && cp .env.example .env && chmod 600 .env && docker compose up -d
cd portainer  && cp .env.example .env && chmod 600 .env && docker compose up -d
```

Sur un VPS à 1 Go de RAM, mieux vaut s'en passer.

## Le fichier à ne jamais supprimer

`traefik/acme.json` contient tous les certificats émis et le compte ACME. Il reste à cet emplacement,
en mode 600. Le supprimer obligerait à redemander tous les certificats d'un coup (quotas Let's Encrypt :
5 certificats par semaine et par domaine) et couperait HTTPS sur toute la plateforme.

```bash
cp traefik/acme.json ~/acme-$(date +%F).json && chmod 600 ~/acme-$(date +%F).json
```

## Vérifier que tout est en place

```bash
cd traefik && ./update-domains.sh      # domaines déclarés + certificat présent + réponse HTTPS
cd wordpress/monsite && docker compose ps
curl -I https://monsite.com
```

## Accéder à vos interfaces

- Site : `https://monsite.com` (puis `/wp-admin` pour l'administration WordPress)
- Dashboard Traefik : optionnel, à activer explicitement (voir `traefik/README.md`)

## Optimiser un petit VPS

- Laisser monitoring et Portainer désactivés
- `INNODB_BUFFER_POOL_SIZE=128M` dans le `.env` du site (au lieu de 256M)
- Ne pas multiplier les extensions WordPress
- Réduire la fréquence des sauvegardes via `RETENTION_DAYS` dans `backup.sh`

> Pour toute question, ouvrir une issue sur GitHub ou consulter la [FAQ](faq_lite.md).
