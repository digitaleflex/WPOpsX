#!/usr/bin/env bash
# =============================================================================
# WPOpsX — Mises à jour d'un site WordPress
# -----------------------------------------------------------------------------
#   ./update.sh
#
# Installed by deploy.sh in the site directory.
#   - met à jour les images (dont le watchdog WordPress)
#   - met à jour le cœur, les extensions, les thèmes et les traductions
#
# ⚠️ Les mises à jour d'extensions automatiques peuvent casser un site : ce
#    script journalise tout ce qu'il fait, et une sauvegarde manuelle reste la
#    règle avant de le laisser tourner en cron.
# =============================================================================
set -euo pipefail
# Le PATH de cron est minimal : on AJOUTE les binaires système au PATH
# existant. Le remplacer casserait Docker installé ailleurs (snap, desktop).
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH}"

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ -f .env ] || { echo "update: .env introuvable dans $PWD" >&2; exit 1; }
set -a; . ./.env; set +a
: "${SITE_NAME:?SITE_NAME absent de .env}"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

log "mise à jour de ${SITE_NAME}"

# --- 1. Images ---------------------------------------------------------------
log "docker compose pull"
docker compose pull --quiet || log "avertissement: pull partiel (registre indisponible ?)"

log "docker compose up -d"
docker compose up -d

# --- 2. WordPress ------------------------------------------------------------
if ! docker compose ps --status running --services 2>/dev/null | grep -qx wordpress; then
    log "ERREUR: le conteneur wordpress n'est pas en cours d'exécution — mises à jour annulées"
    exit 1
fi

wp() { docker compose exec -T wordpress wp "$@" --allow-root; }

if ! wp --info >/dev/null 2>&1; then
    log "ERREUR: wp-cli est absent de l'image — mises à jour WordPress impossibles"
    exit 1
fi

log "wp core update"
wp core update || log "avertissement: 'wp core update' en échec"

log "wp plugin update --all"
wp plugin update --all || log "avertissement: certaines extensions n'ont pas pu être mises à jour"

log "wp theme update --all"
wp theme update --all || log "avertissement: certains thèmes n'ont pas pu être mis à jour"

log "wp language core update"
wp language core update || log "avertissement: traductions non mises à jour"

log "wp core update-db"
wp core update-db || log "avertissement: mise à jour de la base impossible"

log "état des mises à jour restantes :"
wp core check-update || true

log "mise à jour terminée"
