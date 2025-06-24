#!/bin/bash

# Script de restauration automatique pour un site WordPress déployé avec WPOpsX
# Usage : ./restore.sh <site_name> <backup_date>
# Exemple : ./restore.sh testsite 20240610_153000

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SITE_NAME="$1"
BACKUP_DATE="$2"
BACKUP_DIR="../backups/${SITE_NAME}"
SITE_DIR="../${SITE_NAME}"
LOG_FILE="restore_${SITE_NAME}.log"

# Variables de progression
TOTAL_STEPS=7
CURRENT_STEP=0
START_TIME=$(date +%s)

show_progress() {
  CURRENT_STEP=$((CURRENT_STEP + 1))
  local percentage=$((CURRENT_STEP * 100 / TOTAL_STEPS))
  local progress_bar="["
  local completed=$((percentage / 5))
  local remaining=$((20 - completed))
  for ((i=0; i<completed; i++)); do progress_bar+="="; done
  for ((i=0; i<remaining; i++)); do progress_bar+=" "; done
  progress_bar+="]"
  local now=$(date +%s)
  local elapsed=$((now - START_TIME))
  local avg_step=$((elapsed / CURRENT_STEP))
  local est_total=$((avg_step * TOTAL_STEPS))
  local est_left=$((est_total - elapsed))
  echo -e "${BLUE}Progression: $progress_bar $percentage% | Étape $CURRENT_STEP/$TOTAL_STEPS | Temps écoulé: ${elapsed}s | Estimé restant: ${est_left}s${NC}"
  echo "Progression: $progress_bar $percentage% | Étape $CURRENT_STEP/$TOTAL_STEPS | Temps écoulé: ${elapsed}s | Estimé restant: ${est_left}s" >> "$LOG_FILE"
}

# 0. Vérification des permissions et de l'espace disque
info "Vérification des permissions et de l'espace disque..."
if [ ! -w "$BACKUP_DIR" ]; then
  echo -e "${RED}Pas de permission d'écriture sur le dossier de backup ($BACKUP_DIR).${NC}"
  exit 10
fi
if [ ! -w "$SITE_DIR" ]; then
  echo -e "${RED}Pas de permission d'écriture sur le dossier du site ($SITE_DIR).${NC}"
  exit 11
fi
DISK_AVAIL=$(df -Pk "$SITE_DIR" | awk 'NR==2 {print $4}')
if [ "$DISK_AVAIL" -lt 1048576 ]; then # Moins de 1 Go
  echo -e "${RED}Moins de 1 Go d'espace disque disponible sur $SITE_DIR. Restauration risquée.${NC}"
  exit 12
fi
show_progress

# Vérification des variables d'environnement critiques
info "Vérification des variables d'environnement..."
if [ -f "${SITE_DIR}/.env" ]; then
  export $(grep -v '^#' "${SITE_DIR}/.env" | xargs)
fi
if [ -z "$MYSQL_ROOT_PASSWORD" ] || [ -z "$MYSQL_DATABASE" ]; then
  echo -e "${RED}Variables d'environnement MySQL manquantes dans .env. Restauration annulée.${NC}"
  exit 13
fi
show_progress

# Vérification que le port 8080 (WordPress) et 3306 (MySQL) ne sont pas déjà utilisés
info "Vérification des ports Docker..."
if lsof -i :8080 | grep -q LISTEN; then
  echo -e "${RED}Le port 8080 (WordPress) est déjà utilisé. Arrêtez le service concerné avant de restaurer.${NC}"
  exit 14
fi
if lsof -i :3306 | grep -q LISTEN; then
  echo -e "${RED}Le port 3306 (MySQL) est déjà utilisé. Arrêtez le service concerné avant de restaurer.${NC}"
  exit 15
fi
show_progress

# 1. Vérification des arguments et des fichiers
show_progress

if [ -z "$SITE_NAME" ] || [ -z "$BACKUP_DATE" ]; then
  echo -e "${YELLOW}Usage : $0 <site_name> <backup_date>\nExemple : $0 testsite 20240610_153000${NC}"
  exit 1
fi

DB_DUMP="${BACKUP_DIR}/db_${BACKUP_DATE}.sql"
FILES_ARCHIVE="${BACKUP_DIR}/files_${BACKUP_DATE}.tar.gz"

if [ ! -f "$DB_DUMP" ] || [ ! -f "$FILES_ARCHIVE" ]; then
  echo -e "${RED}Sauvegarde introuvable pour la date ${BACKUP_DATE} dans ${BACKUP_DIR}${NC}"
  exit 2
fi

if [ ! -s "$DB_DUMP" ]; then
  echo -e "${RED}Le fichier de sauvegarde SQL ($DB_DUMP) est vide. Restauration annulée.${NC}"
  exit 3
fi

# 2. Arrêt des services Docker
info "Arrêt des services Docker..."
docker-compose -f "${SITE_DIR}/docker-compose.yml" down >> "$LOG_FILE" 2>&1
show_progress

# 3. Vérification de l'intégrité de l'archive fichiers
info "Vérification de l'intégrité de l'archive WordPress..."
if ! tar -tzf "$FILES_ARCHIVE" &>/dev/null; then
  echo -e "${RED}L'archive de fichiers WordPress est corrompue. Restauration annulée.${NC}"
  exit 4
fi
show_progress

# 4. Restauration des fichiers WordPress
info "Restauration des fichiers WordPress..."
rm -rf "${SITE_DIR}/wordpress"
tar -xzf "$FILES_ARCHIVE" -C "$SITE_DIR" >> "$LOG_FILE" 2>&1
show_progress

# 5. Redémarrage de la base de données
info "Redémarrage de la base de données..."
docker-compose -f "${SITE_DIR}/docker-compose.yml" up -d mysql_${SITE_NAME} >> "$LOG_FILE" 2>&1
sleep 10
# Check MySQL up
if ! docker-compose -f "${SITE_DIR}/docker-compose.yml" exec -T mysql_${SITE_NAME} mysqladmin ping -u root --password=${MYSQL_ROOT_PASSWORD:-root} | grep -q 'mysqld is alive'; then
  echo -e "${RED}La base de données ne démarre pas correctement. Restauration annulée.${NC}"
  exit 5
fi
show_progress

# 6. Restauration de la base de données
info "Restauration de la base de données..."
if [ -f "${SITE_DIR}/.env" ]; then
  export $(grep -v '^#' "${SITE_DIR}/.env" | xargs)
fi
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-root}
MYSQL_DATABASE=${MYSQL_DATABASE:-wordpress_${SITE_NAME}}
docker-compose -f "${SITE_DIR}/docker-compose.yml" exec -T mysql_${SITE_NAME} mysql -u root -p${MYSQL_ROOT_PASSWORD} ${MYSQL_DATABASE} < "$DB_DUMP" >> "$LOG_FILE" 2>&1
show_progress

# 7. Redémarrage de tous les services
info "Redémarrage de tous les services..."
docker-compose -f "${SITE_DIR}/docker-compose.yml" up -d >> "$LOG_FILE" 2>&1
sleep 10
# Check WordPress up
if ! curl -sL http://localhost:8080 | grep -iq "wordpress"; then
  warning "Le site WordPress ne répond pas encore. Vérifiez les logs si le problème persiste."
else
  success "Le site WordPress est de nouveau accessible."
fi
show_progress

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
echo -e "${GREEN}Restauration terminée pour ${SITE_NAME} à partir de la sauvegarde du ${BACKUP_DATE} en ${DURATION}s.${NC}"
echo "Restauration terminée pour ${SITE_NAME} à partir de la sauvegarde du ${BACKUP_DATE} en ${DURATION}s." >> "$LOG_FILE" 