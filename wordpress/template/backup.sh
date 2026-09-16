#!/usr/bin/env bash
# =============================================================================
# WPOpsX — Sauvegarde d'un site (base de données + fichiers)
# -----------------------------------------------------------------------------
#   ./backup.sh
#
# Installed by deploy.sh in the site directory. Lit les identifiants depuis
# .env (aucun secret n'est écrit dans ce script ni dans la crontab).
#
# Contenu d'une sauvegarde : db.sql.gz (base) + files.tar.gz (/var/www/html).
# Restauration complète (voir aussi wordpress/template/README.md) :
#
#   gunzip -c backups/<horodatage>/db.sql.gz | \
#       docker compose exec -T mysql sh -c 'exec mysql -u root "$MYSQL_DATABASE"'
#
#   docker compose exec -T wordpress sh -c 'tar xzf - -C /var/www/html' \
#       < backups/<horodatage>/files.tar.gz
#
# Note : les deux étapes lisent/écrivent via la sortie standard, aucun chemin de
# l'hôte n'est monté — les caractères « : » et « / » des chemins ne peuvent donc
# pas être réinterprétés par l'interpréteur de commandes.
# =============================================================================
set -euo pipefail
# Le PATH de cron est minimal : on AJOUTE les binaires système au PATH
# existant. Le remplacer casserait Docker installé ailleurs (snap, desktop).
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH}"

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ -f .env ] || { echo "backup: .env introuvable dans $PWD" >&2; exit 1; }
set -a; . ./.env; set +a
: "${SITE_NAME:?SITE_NAME absent de .env}"
: "${MYSQL_DATABASE:?MYSQL_DATABASE absent de .env}"
: "${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD absent de .env}"

RETENTION_DAYS="${RETENTION_DAYS:-7}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_ROOT="${PWD}/backups"
BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"
WORDPRESS_IMAGE="${WORDPRESS_IMAGE:-eflexcloud/wordpress-custom}"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

# La base doit tourner pour être dumpée : message clair plutôt qu'une erreur brute.
if ! docker compose ps --status running --services 2>/dev/null | grep -qx mysql; then
    log "ERREUR: le conteneur mysql n'est pas en cours d'exécution — sauvegarde annulée"
    exit 1
fi

mkdir -p "$BACKUP_DIR"
log "début de la sauvegarde de ${SITE_NAME} -> ${BACKUP_DIR}"

# --- 1. Base de données ------------------------------------------------------
# Le mot de passe passe par l'environnement du processus dans le conteneur
# (MYSQL_PWD) et non par la ligne de commande : il n'apparaît donc pas dans les
# `ps` de l'hôte.
log "dump de la base ${MYSQL_DATABASE}..."
docker compose exec -T -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql \
    sh -c 'exec mysqldump -u root --single-transaction --quick --lock-tables=false "$MYSQL_DATABASE"' \
    > "${BACKUP_DIR}/db.sql"

# Un dump interrompu produit un fichier tronqué qui a l'air valide : on vérifie
# la ligne de fin émise par mysqldump, sinon on supprime l'artefact.
if ! grep -q "Dump completed" "${BACKUP_DIR}/db.sql"; then
    rm -f "${BACKUP_DIR}/db.sql"
    log "ERREUR: dump incomplet ou vide — sauvegarde annulée (conteneur arrêté ?)"
    exit 1
fi
if command -v gzip >/dev/null 2>&1; then
    gzip -f "${BACKUP_DIR}/db.sql"
    log "base sauvegardée : db.sql.gz ($(du -h "${BACKUP_DIR}/db.sql.gz" | cut -f1))"
else
    log "base sauvegardée : db.sql ($(du -h "${BACKUP_DIR}/db.sql" | cut -f1)) — gzip absent, non compressée"
fi

# --- 2. Fichiers (volume Docker, pas un dossier hôte) ------------------------
# L'archive est produite par le conteneur et écrite sur la sortie standard :
# aucun chemin de l'hôte n'est monté, donc aucun risque de conversion de chemin
# (Git-Bash/MSYS transforme les arguments ressemblant à des chemins).
log "archive des fichiers WordPress..."
if ! docker compose ps --status running --services 2>/dev/null | tr -d '\r' | grep -qx wordpress; then
    log "ERREUR: le conteneur wordpress n'est pas en cours d'exécution — sauvegarde des fichiers impossible"
    exit 1
fi
docker compose exec -T wordpress sh -c 'tar czf - -C /var/www/html .' > "${BACKUP_DIR}/files.tar.gz"

# Vérifie que l'archive est lisible, sinon la sauvegarde n'est pas fiable.
if ! tar tzf "${BACKUP_DIR}/files.tar.gz" >/dev/null 2>&1; then
    log "ERREUR: archive illisible — sauvegarde annulée"
    exit 1
fi
log "fichiers sauvegardés : files.tar.gz ($(du -h "${BACKUP_DIR}/files.tar.gz" | cut -f1))"

# --- 3. Rotation ------------------------------------------------------------
deleted=$(find "$BACKUP_ROOT" -maxdepth 1 -mindepth 1 -type d -mtime "+${RETENTION_DAYS}" -print -exec rm -rf {} \; 2>/dev/null | wc -l)
log "rotation : ${deleted} sauvegarde(s) de plus de ${RETENTION_DAYS} jours supprimée(s)"
log "sauvegarde terminée"
