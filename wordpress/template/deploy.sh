#!/bin/bash

# Configuration par défaut
DEFAULT_APP_TYPE="wordpress"
DEFAULT_MYSQL_VERSION="10.11"
DEFAULT_REDIS_VERSION="7-alpine"
DEFAULT_WORDPRESS_VERSION="latest"
DEFAULT_WORDPRESS_IMAGE="eflexcloud/wordpress-custom"

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables pour le suivi
TOTAL_STEPS=10
CURRENT_STEP=0
DEPLOYMENT_LOG="deployment.log"

# Fonction pour afficher les messages d'erreur
error() {
    echo -e "${RED}[ERREUR]${NC} $1"
    echo "[ERREUR] $1" >> "$DEPLOYMENT_LOG"
    exit 1
}

# Fonction pour afficher les messages de succès
success() {
    echo -e "${GREEN}[SUCCÈS]${NC} $1"
    echo "[SUCCÈS] $1" >> "$DEPLOYMENT_LOG"
}

# Fonction pour afficher les messages d'avertissement
warning() {
    echo -e "${YELLOW}[ATTENTION]${NC} $1"
    echo "[ATTENTION] $1" >> "$DEPLOYMENT_LOG"
}

# Fonction pour afficher les messages d'information
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[INFO] $1" >> "$DEPLOYMENT_LOG"
}

# Fonction pour afficher la progression
show_progress() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local percentage=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    local progress_bar="["
    local completed=$((percentage / 5))
    local remaining=$((20 - completed))
    
    for ((i=0; i<completed; i++)); do
        progress_bar+="="
    done
    for ((i=0; i<remaining; i++)); do
        progress_bar+=" "
    done
    progress_bar+="]"
    
    echo -e "${BLUE}Progression: $progress_bar $percentage%${NC}"
    echo "Progression: $progress_bar $percentage%" >> "$DEPLOYMENT_LOG"
}

# Fonction pour initialiser le log
init_log() {
    echo "=== Déploiement démarré le $(date) ===" > "$DEPLOYMENT_LOG"
    echo "Type d'application: $APP_TYPE" >> "$DEPLOYMENT_LOG"
    echo "Nom du site: $SITE_NAME" >> "$DEPLOYMENT_LOG"
    echo "Domaine: $DOMAIN_NAME" >> "$DEPLOYMENT_LOG"
    echo "=====================================" >> "$DEPLOYMENT_LOG"
}

# Fonction pour afficher l'aide
show_help() {
    echo "Usage: $0 [options] <site_name> <domain_name>"
    echo ""
    echo "Options:"
    echo "  -t, --type TYPE       Type d'application (wordpress, laravel, etc.)"
    echo "  -m, --mysql VER       Version de MySQL/MariaDB"
    echo "  -r, --redis VER       Version de Redis"
    echo "  -w, --wp VER          Version de WordPress (si type=wordpress)"
    echo "  -i, --wp-image IMG    Image WordPress à utiliser (par défaut eflexcloud/wordpress-custom)"
    echo "  -h, --help            Affiche cette aide"
    echo ""
    echo "Exemples:"
    echo "  $0 -t wordpress blog blog.digitaleflex.com"
    echo "  $0 -t laravel api api.monsite.com"
    echo "  $0 --type wordpress --mysql 10.11 --redis 7-alpine --wp-image eflexcloud/wordpress-custom blog blog.digitaleflex.com"
}

# Fonction pour vérifier si un domaine est valide
check_domain() {
    info "Vérification du domaine $DOMAIN_NAME..."
    if [[ ! $DOMAIN_NAME =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*(\.[a-zA-Z0-9][a-zA-Z0-9-]*)*\.[a-zA-Z]{2,}$ ]]; then
        error "Le domaine '$DOMAIN_NAME' n'est pas valide"
    fi
    success "Domaine valide"
    show_progress
}

# Fonction pour vérifier les permissions d'un répertoire
check_directory_permissions() {
    local dir=$1
    info "Vérification des permissions du répertoire: $dir"
    if [ ! -w "$dir" ]; then
        error "Pas de permission d'écriture sur le répertoire: $dir"
    fi
    success "Permissions OK"
    show_progress
}

# Fonction pour vérifier si Docker est installé et en cours d'exécution
check_docker() {
    info "Vérification de l'installation Docker..."
    if ! command -v docker &> /dev/null; then
        error "Docker n'est pas installé"
    fi
    if ! docker info &> /dev/null; then
        error "Docker n'est pas en cours d'exécution"
    fi
    success "Docker est installé et en cours d'exécution"
    show_progress
}

# Fonction pour vérifier si docker-compose est installé
check_docker_compose() {
    info "Vérification de l'installation docker-compose..."
    if ! command -v docker-compose &> /dev/null; then
        error "docker-compose n'est pas installé"
    fi
    success "docker-compose est installé"
    show_progress
}

# Fonction pour vérifier et installer les dépendances système
check_system_dependencies() {
    info "Vérification des dépendances système..."
    
    local dependencies=(
        "curl"
        "wget"
        "unzip"
        "git"
        "openssl"
        "jq"
    )
    
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            info "Installation de $dep..."
            apt-get update && apt-get install -y "$dep" || warning "Impossible d'installer $dep"
        fi
    done
    
    success "Dépendances système vérifiées"
    show_progress
}

# Fonction pour configurer les sauvegardes automatiques
setup_auto_backups() {
    info "Configuration des sauvegardes automatiques..."
    
    local backup_script="/usr/local/bin/backup-${SITE_NAME}.sh"
    
    # Créer le script de sauvegarde
    cat > "$backup_script" << EOF
#!/bin/bash
# Script de sauvegarde automatique pour ${SITE_NAME}

BACKUP_DIR="/home/audest/backups/${SITE_NAME}"
TIMESTAMP=\$(date +%Y%m%d_%H%M%S)

# Créer le dossier de sauvegarde
mkdir -p "\$BACKUP_DIR"

# Sauvegarder la base de données
docker-compose -f /home/audest/my_arch/wordpress/${SITE_NAME}/docker-compose.yml exec -T mysql_${SITE_NAME} mysqldump -u root -p${MYSQL_ROOT_PASSWORD} ${MYSQL_DATABASE} > "\$BACKUP_DIR/db_\$TIMESTAMP.sql"

# Sauvegarder les fichiers WordPress
tar -czf "\$BACKUP_DIR/files_\$TIMESTAMP.tar.gz" -C /home/audest/my_arch/wordpress/${SITE_NAME} wordpress

# Supprimer les sauvegardes plus anciennes que 7 jours
find "\$BACKUP_DIR" -type f -mtime +7 -delete
EOF
    
    # Rendre le script exécutable
    chmod +x "$backup_script"
    
    # Ajouter une tâche cron pour les sauvegardes quotidiennes
    (crontab -l 2>/dev/null; echo "0 2 * * * $backup_script") | crontab -
    
    success "Sauvegardes automatiques configurées"
    show_progress
}

# Fonction pour configurer la surveillance
setup_monitoring() {
    info "Configuration de la surveillance..."
    
    # Vérifier si Prometheus est installé
    if ! docker ps | grep -q "prometheus"; then
        info "Installation de Prometheus..."
        docker run -d \
            --name prometheus \
            --network proxy \
            -p 9090:9090 \
            -v /etc/prometheus:/etc/prometheus \
            prom/prometheus
    fi
    
    # Vérifier si Grafana est installé
    if ! docker ps | grep -q "grafana"; then
        info "Installation de Grafana..."
        docker run -d \
            --name grafana \
            --network proxy \
            -p 3000:3000 \
            grafana/grafana
    fi
    
    success "Surveillance configurée"
    show_progress
}

# Fonction pour configurer les mises à jour automatiques
setup_auto_updates() {
    info "Configuration des mises à jour automatiques..."
    
    local update_script="/usr/local/bin/update-${SITE_NAME}.sh"
    
    # Créer le script de mise à jour
    cat > "$update_script" << EOF
#!/bin/bash
# Script de mise à jour automatique pour ${SITE_NAME}

cd /home/audest/my_arch/wordpress/${SITE_NAME}

# Mettre à jour les conteneurs
docker-compose pull
docker-compose up -d

# Mettre à jour WordPress
docker-compose exec -T wordpress_${SITE_NAME} wp core update --allow-root
docker-compose exec -T wordpress_${SITE_NAME} wp plugin update --all --allow-root
docker-compose exec -T wordpress_${SITE_NAME} wp theme update --all --allow-root
docker-compose exec -T wordpress_${SITE_NAME} wp language update --allow-root
EOF
    
    # Rendre le script exécutable
    chmod +x "$update_script"
    
    # Ajouter une tâche cron pour les mises à jour hebdomadaires
    (crontab -l 2>/dev/null; echo "0 3 * * 0 $update_script") | crontab -
    
    success "Mises à jour automatiques configurées"
    show_progress
}

# Fonction pour configurer la sécurité
setup_security() {
    info "Configuration de la sécurité..."
    
    # Configurer les limites de ressources
    cat > /etc/security/limits.d/wordpress.conf << EOF
www-data soft nofile 65535
www-data hard nofile 65535
EOF
    
    success "Sécurité configurée"
    show_progress
}

# Fonction pour nettoyer les ressources existantes
cleanup_existing_resources() {
    info "Nettoyage des ressources existantes..."
    
    # Arrêter et supprimer les conteneurs existants
    if docker ps -a | grep -q "${SITE_NAME}"; then
        info "Suppression des conteneurs existants..."
        docker-compose down --remove-orphans -v || warning "Erreur lors de la suppression des conteneurs"
    fi
    
    # Supprimer les volumes existants
    local volumes=(
        "wordpress_files_${SITE_NAME}"
        "wordpress_content_${SITE_NAME}"
        "wordpress_uploads_${SITE_NAME}"
        "wordpress_themes_${SITE_NAME}"
        "wordpress_plugins_${SITE_NAME}"
        "db_data_${SITE_NAME}"
        "redis_data_${SITE_NAME}"
    )
    
    for volume in "${volumes[@]}"; do
        if docker volume ls | grep -q "$volume"; then
            info "Suppression du volume $volume..."
            docker volume rm "$volume" || warning "Erreur lors de la suppression du volume $volume"
        fi
    done
    
    # Supprimer les réseaux existants
    if docker network ls | grep -q "${SITE_NAME}_network"; then
        info "Suppression du réseau ${SITE_NAME}_network..."
        docker network rm "${SITE_NAME}_network" || warning "Erreur lors de la suppression du réseau"
    fi
    
    success "Nettoyage terminé"
    show_progress
}

# Fonction pour configurer les permissions WordPress
setup_wordpress_permissions() {
    info "Configuration des permissions WordPress..."
    
    # Définir les variables
    local wp_dir="../${SITE_NAME}/wordpress"
    local wp_content="${wp_dir}/wp-content"
    local wp_uploads="${wp_content}/uploads"
    local wp_plugins="${wp_content}/plugins"
    local wp_themes="${wp_content}/themes"
    local wp_languages="${wp_content}/languages"
    
    # Créer les dossiers s'ils n'existent pas
    mkdir -p "$wp_uploads" "$wp_plugins" "$wp_themes" "$wp_languages"
    
    # Créer la structure des dossiers pour les uploads
    local current_year=$(date +%Y)
    local current_month=$(date +%m)
    mkdir -p "${wp_uploads}/${current_year}/${current_month}"
    
    # Définir le propriétaire www-data (33:33)
    chown -R 33:33 "$wp_dir" || warning "Impossible de changer le propriétaire des fichiers WordPress"
    
    # Permissions de base pour le dossier WordPress
    find "$wp_dir" -type d -exec chmod 755 {} \;
    find "$wp_dir" -type f -exec chmod 644 {} \;
    
    # Permissions spéciales pour wp-content et ses sous-dossiers
    chmod -R 775 "$wp_content"
    
    # Permissions spécifiques pour les dossiers critiques
    chmod -R 775 "$wp_uploads"
    chmod -R 775 "$wp_plugins"
    chmod -R 775 "$wp_themes"
    chmod -R 775 "$wp_languages"
    
    # Permissions spéciales pour les fichiers de configuration
    if [ -f "${wp_dir}/wp-config.php" ]; then
        chmod 640 "${wp_dir}/wp-config.php"
    fi
    
    # Permissions pour les fichiers .htaccess
    find "$wp_dir" -name ".htaccess" -exec chmod 644 {} \;
    
    # Permissions pour les fichiers exécutables
    find "$wp_dir" -type f -name "*.php" -exec chmod 644 {} \;
    find "$wp_dir" -type f -name "*.sh" -exec chmod 755 {} \;
    
    # Permissions pour les fichiers de cache
    if [ -d "${wp_content}/cache" ]; then
        chmod -R 775 "${wp_content}/cache"
    fi
    
    # Permissions pour les fichiers de mise à jour
    if [ -d "${wp_content}/upgrade" ]; then
        chmod -R 775 "${wp_content}/upgrade"
    fi
    
    # Permissions pour les fichiers de debug
    if [ -d "${wp_content}/debug.log" ]; then
        chmod 664 "${wp_content}/debug.log"
    fi
    
    # S'assurer que les dossiers d'uploads sont accessibles en écriture
    chmod -R 775 "${wp_uploads}"
    chown -R 33:33 "${wp_uploads}"
    
    # Créer un fichier .htaccess dans le dossier uploads pour la sécurité
    cat > "${wp_uploads}/.htaccess" << EOF
Options -Indexes
<FilesMatch "\.(php|php3|php4|php5|phtml|pl|py|jsp|asp|htm|html|shtml|sh|cgi)$">
    Order Deny,Allow
    Deny from all
</FilesMatch>
EOF
    
    success "Permissions WordPress configurées avec succès"
    show_progress
}

# Fonction pour créer la structure du site
create_site_structure() {
    info "Création de la structure du site..."
    
    # Supprimer le dossier existant s'il existe
    if [ -d "../$SITE_NAME" ]; then
        info "Suppression du dossier existant..."
        rm -rf "../$SITE_NAME" || error "Impossible de supprimer le dossier existant"
    fi
    
    mkdir -p "../$SITE_NAME" || error "Impossible de créer le dossier du site"
    chmod 755 "../$SITE_NAME" || error "Impossible de définir les permissions du dossier du site"
    
    # Créer uniquement les dossiers pour les données persistantes
    cd "../$SITE_NAME" || error "Impossible d'accéder au dossier du site"
    mkdir -p "mysql/data" "redis/data" || error "Erreur lors de la création des dossiers"

    # Permissions pour les fichiers de configuration
    touch .env
    chmod 644 .env
    touch docker-compose.yml
    chmod 644 docker-compose.yml

    success "Structure du site créée avec succès"
    show_progress
}

# Fonction pour vérifier les permissions après le démarrage
check_wordpress_permissions() {
    info "Vérification des permissions WordPress..."
    
    # Vérifier les permissions des dossiers critiques
    local wp_dir="../${SITE_NAME}/wordpress"
    local wp_content="${wp_dir}/wp-content"
    local wp_uploads="${wp_content}/uploads"
    local wp_plugins="${wp_content}/plugins"
    local wp_themes="${wp_content}/themes"
    
    # Vérifier le propriétaire
    if [ "$(stat -c '%u:%g' "$wp_dir")" != "33:33" ]; then
        warning "Le propriétaire du dossier WordPress n'est pas www-data"
        setup_wordpress_permissions
    fi
    
    # Vérifier les permissions des dossiers
    for dir in "$wp_content" "$wp_uploads" "$wp_plugins" "$wp_themes"; do
        if [ ! -w "$dir" ]; then
            warning "Le dossier $dir n'est pas accessible en écriture"
            setup_wordpress_permissions
        fi
    done
    
    # Vérifier spécifiquement les permissions du dossier uploads
    local current_year=$(date +%Y)
    local current_month=$(date +%m)
    local upload_dir="${wp_uploads}/${current_year}/${current_month}"
    
    if [ ! -d "$upload_dir" ]; then
        info "Création du dossier d'uploads pour le mois en cours..."
        mkdir -p "$upload_dir"
        chmod 775 "$upload_dir"
        chown 33:33 "$upload_dir"
    fi
    
    if [ ! -w "$upload_dir" ]; then
        warning "Le dossier d'uploads n'est pas accessible en écriture"
        chmod 775 "$upload_dir"
        chown 33:33 "$upload_dir"
    fi
    
    success "Permissions WordPress vérifiées"
    show_progress
}

# Fonction pour générer les fichiers de configuration
generate_config_files() {
    info "Génération des fichiers de configuration..."
    
    # Générer des mots de passe sécurisés
    DB_PASSWORD=$(openssl rand -base64 32)
    REDIS_PASSWORD=$(openssl rand -base64 32)
    MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32)
    
    # Générer les fichiers
    generate_docker_compose "$APP_TYPE" "$SITE_NAME" "$MYSQL_VERSION" "$REDIS_VERSION" "$WP_VERSION" "$WORDPRESS_IMAGE"
    generate_env_file "$APP_TYPE" "$SITE_NAME" "$DOMAIN_NAME" "$DB_PASSWORD" "$REDIS_PASSWORD" "$MYSQL_ROOT_PASSWORD"
    
    success "Fichiers de configuration générés"
    show_progress
}

# Fonction pour vérifier l'espace disque
check_disk_space() {
    info "Vérification de l'espace disque..."
    DISK_SPACE=$(df -h . | awk 'NR==2 {print $4}' | sed 's/G//')
    if (( $(echo "$DISK_SPACE < 5" | bc -l) )); then
        warning "Attention: Moins de 5GB d'espace disque disponible ($DISK_SPACE GB)"
    else
        success "Espace disque suffisant ($DISK_SPACE GB)"
    fi
    show_progress
}

# Fonction pour démarrer les services
start_services() {
    info "Démarrage des services..."
    
    # Nettoyer les ressources existantes
    cleanup_existing_resources
    
    # Démarrer les services
    info "Démarrage des nouveaux services..."
    docker-compose up -d || error "Erreur lors du démarrage des services"
    
    # Attendre que les services soient prêts
    info "Attente du démarrage des services..."
    local max_retries=30
    local retry_count=0
    local services_ready=false
    
    while [ $retry_count -lt $max_retries ] && [ "$services_ready" = false ]; do
        if docker-compose ps | grep -q "Up" && \
           docker-compose exec -T mysql_${SITE_NAME} mysqladmin ping -h localhost -u root -p${MYSQL_ROOT_PASSWORD} &>/dev/null && \
           docker-compose exec -T redis_${SITE_NAME} redis-cli -a ${REDIS_PASSWORD} ping &>/dev/null; then
            services_ready=true
            break
        fi
        retry_count=$((retry_count + 1))
        sleep 2
        echo -n "."
    done
    echo ""
    
    if [ "$services_ready" = false ]; then
        error "Les services ne sont pas démarrés correctement après $max_retries tentatives"
    fi
    
    # Vérifier la création de la base de données
    info "Vérification de la base de données..."
    if ! docker-compose exec -T mysql_${SITE_NAME} mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "USE ${MYSQL_DATABASE};" &>/dev/null; then
        info "Création de la base de données..."
        docker-compose exec -T mysql_${SITE_NAME} mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "CREATE DATABASE IF NOT EXISTS ${MYSQL_DATABASE} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" || error "Erreur lors de la création de la base de données"
        docker-compose exec -T mysql_${SITE_NAME} mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';" || error "Erreur lors de l'attribution des privilèges"
        docker-compose exec -T mysql_${SITE_NAME} mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "FLUSH PRIVILEGES;" || error "Erreur lors du flush des privilèges"
    fi
    
    # Vérifier les permissions après le démarrage
    check_wordpress_permissions
    
    success "Services démarrés avec succès"
    show_progress
}

# Fonction pour vérifier les logs
check_logs() {
    info "Vérification des logs..."
    if docker-compose logs | grep -i "error\|exception\|fatal"; then
        warning "Des erreurs ont été détectées dans les logs"
    else
        success "Aucune erreur détectée dans les logs"
    fi
    show_progress
}

# Fonction pour vérifier les volumes Docker
check_docker_volumes() {
    info "Vérification des volumes Docker..."
    local volumes=(
        "wordpress_files_${SITE_NAME}"
        "wordpress_content_${SITE_NAME}"
        "wordpress_uploads_${SITE_NAME}"
        "wordpress_themes_${SITE_NAME}"
        "wordpress_plugins_${SITE_NAME}"
        "mysql_data"
        "redis_data"
    )
    
    for volume in "${volumes[@]}"; do
        if ! docker volume inspect "$volume" &>/dev/null; then
            warning "Le volume $volume n'existe pas, création..."
            docker volume create "$volume" || error "Impossible de créer le volume $volume"
        fi
    done
    success "Volumes Docker vérifiés"
    show_progress
}

# Fonction pour vérifier les certificats SSL
check_ssl_certificates() {
    info "Vérification des certificats SSL..."
    sleep 10  # Attendre que les certificats soient générés
    
    if ! openssl s_client -connect "${DOMAIN_NAME}:443" -servername "${DOMAIN_NAME}" </dev/null 2>/dev/null | grep -q "BEGIN CERTIFICATE"; then
        warning "Le certificat SSL n'est pas encore généré. Cela peut prendre quelques minutes."
    else
        success "Certificat SSL vérifié"
    fi
    show_progress
}

# Fonction pour créer une sauvegarde
create_backup() {
    info "Création d'une sauvegarde..."
    local backup_dir="../backups/${SITE_NAME}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    mkdir -p "$backup_dir"
    
    # Vérifier si le conteneur MySQL est en cours d'exécution
    if docker-compose ps mysql_${SITE_NAME} | grep -q "Up"; then
        # Sauvegarde de la base de données
        if docker-compose exec -T mysql_${SITE_NAME} mysqldump -u root -p${MYSQL_ROOT_PASSWORD} ${MYSQL_DATABASE} > "${backup_dir}/db_${timestamp}.sql"; then
            success "Sauvegarde de la base de données créée"
        else
            warning "Erreur lors de la sauvegarde de la base de données"
        fi
    else
        warning "Le conteneur MySQL n'est pas en cours d'exécution, impossible de sauvegarder la base de données"
    fi
    
    # Sauvegarde des fichiers WordPress
    if [ -d "../${SITE_NAME}/wordpress" ]; then
        if tar -czf "${backup_dir}/files_${timestamp}.tar.gz" -C "../${SITE_NAME}" wordpress; then
            success "Sauvegarde des fichiers créée"
        else
            warning "Erreur lors de la sauvegarde des fichiers"
        fi
    else
        warning "Le dossier WordPress n'existe pas, impossible de sauvegarder les fichiers"
    fi
    
    success "Sauvegarde terminée dans ${backup_dir}"
    show_progress
}

# Fonction pour vérifier la santé du site
check_site_health() {
    info "Vérification de la santé du site..."
    local max_retries=10
    local retry_count=0
    local site_healthy=false
    
    while [ $retry_count -lt $max_retries ] && [ "$site_healthy" = false ]; do
        # Vérifier si WordPress répond
        if curl -s -o /dev/null -w "%{http_code}" "https://${DOMAIN_NAME}" | grep -q "200\|302"; then
            site_healthy=true
            break
        fi
        
        # Vérifier les logs WordPress pour des erreurs spécifiques
        if docker-compose logs wordpress_${SITE_NAME} | grep -q "Error establishing a database connection"; then
            # Vérifier la connexion à la base de données
            if ! docker-compose exec -T mysql_${SITE_NAME} mysql -u ${MYSQL_USER} -p${MYSQL_PASSWORD} -e "USE ${MYSQL_DATABASE};" &>/dev/null; then
                error "Erreur de connexion à la base de données. Vérifiez les identifiants dans le fichier .env"
            fi
        fi
        
        retry_count=$((retry_count + 1))
        sleep 5
        echo -n "."
    done
    echo ""
    
    if [ "$site_healthy" = true ]; then
        success "Le site répond correctement"
    else
        warning "Le site ne répond pas après $max_retries tentatives"
        info "Vérification des logs pour plus de détails..."
        docker-compose logs wordpress_${SITE_NAME}
    fi
    show_progress
}

# Fonction pour vérifier les mises à jour WordPress
check_wordpress_updates() {
    info "Vérification des mises à jour WordPress..."
    
    # Vérifier si le conteneur WordPress est en cours d'exécution
    if ! docker-compose ps wordpress_${SITE_NAME} | grep -q "Up"; then
        warning "Le conteneur WordPress n'est pas en cours d'exécution"
        return
    fi
    
    # Vérifier si la base de données est accessible
    if ! docker-compose exec -T mysql_${SITE_NAME} mysqladmin ping -h localhost -u root -p${MYSQL_ROOT_PASSWORD} &>/dev/null; then
        warning "La base de données n'est pas accessible"
        return
    fi
    
    # Vérifier les mises à jour
    if docker-compose exec -T wordpress_${SITE_NAME} wp core check-update --allow-root 2>/dev/null | grep -q "Success"; then
        warning "Des mises à jour WordPress sont disponibles"
    else
        success "WordPress est à jour"
    fi
    show_progress
}

# Fonction pour vérifier l'accessibilité du site
check_site_accessibility() {
    info "Vérification de l'accessibilité du site..."
    sleep 5
    if ! curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN_NAME" | grep -q "200"; then
        warning "Le site n'est pas encore accessible. Cela peut prendre quelques minutes pour que les certificats SSL soient générés."
    else
        success "Le site est accessible"
    fi
    show_progress
}

# Fonction pour afficher le résumé
show_summary() {
    echo -e "\n${GREEN}=== Résumé du déploiement ===${NC}"
    echo "Type d'application: $APP_TYPE"
    echo "Nom du site: $SITE_NAME"
    echo "Domaine: $DOMAIN_NAME"
    echo "URL: https://$DOMAIN_NAME"
    echo "Logs: $DEPLOYMENT_LOG"
    echo -e "${GREEN}============================${NC}\n"
    
    echo "=== Résumé du déploiement ===" >> "$DEPLOYMENT_LOG"
    echo "Type d'application: $APP_TYPE" >> "$DEPLOYMENT_LOG"
    echo "Nom du site: $SITE_NAME" >> "$DEPLOYMENT_LOG"
    echo "Domaine: $DOMAIN_NAME" >> "$DEPLOYMENT_LOG"
    echo "URL: https://$DOMAIN_NAME" >> "$DEPLOYMENT_LOG"
    echo "============================" >> "$DEPLOYMENT_LOG"
}

# Fonction pour générer le docker-compose.yml en fonction du type d'application
generate_docker_compose() {
    local app_type=$1
    local site_name=$2
    local mysql_version=$3
    local redis_version=$4
    local wp_version=$5
    local wp_image=$6

    case $app_type in
        "wordpress")
            cat > docker-compose.yml << EOF
services:
  mysql_${site_name}:  
    image: mariadb:${mysql_version}
    container_name: mysql_wp_${site_name}  
    restart: always
    environment:
      - MYSQL_ROOT_PASSWORD=\${MYSQL_ROOT_PASSWORD}
      - MYSQL_DATABASE=\${MYSQL_DATABASE}
      - MYSQL_USER=\${MYSQL_USER}
      - MYSQL_PASSWORD=\${MYSQL_PASSWORD}
      - MYSQL_CHARACTER_SET_SERVER=utf8mb4
      - MYSQL_COLLATION_SERVER=utf8mb4_unicode_ci
    command: >
      --default-authentication-plugin=mysql_native_password
      --character-set-server=utf8mb4
      --collation-server=utf8mb4_unicode_ci
      --max-connections=500
      --max_allowed_packet=64M
      --innodb_buffer_pool_size=256M
      --innodb_log_file_size=64M
      --innodb_flush_log_at_trx_commit=2
      --innodb_flush_method=O_DIRECT
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "root", "-p\${MYSQL_ROOT_PASSWORD}"]
      interval: 10s
      timeout: 5s
      retries: 5
    volumes:
      - db_data_${site_name}:/var/lib/mysql
    networks:
      - proxy
      - ${site_name}_network
    labels:
      - "traefik.enable=false"

  redis_${site_name}:
    image: redis:${redis_version}
    container_name: redis_${site_name}
    command: redis-server --requirepass \${REDIS_PASSWORD} --appendonly yes
    volumes:
      - redis_data_${site_name}:/data
    networks:
      - ${site_name}_network
      - proxy
      - redis_network
    labels:
      - "traefik.enable=false"
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "\${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  wordpress_${site_name}:  
    image: ${wp_image}
    container_name: wordpress_${site_name} 
    security_opt:
      - no-new-privileges:true
    restart: always 
    environment:
      # Configuration de la base de données
      WORDPRESS_DB_HOST: \${MYSQL_HOST}
      WORDPRESS_DB_NAME: \${MYSQL_DATABASE}
      WORDPRESS_DB_USER: \${MYSQL_USER}
      WORDPRESS_DB_PASSWORD: \${MYSQL_PASSWORD}

      # Configuration PHP
      PHP_MEMORY_LIMIT: \${WP_MEMORY_LIMIT}
      PHP_MAX_EXECUTION_TIME: 300
      PHP_POST_MAX_SIZE: \${WP_POST_MAX_SIZE}
      PHP_UPLOAD_MAX_FILESIZE: \${WP_UPLOAD_MAX_FILESIZE}
      WORDPRESS_DEBUG: \${WP_DEBUG}

      # Configuration Redis
      REDIS_HOST: redis_${site_name}
      REDIS_PASSWORD: \${REDIS_PASSWORD}

      # Configuration du serveur
      APACHE_SERVER_NAME: \${DOMAIN_NAME}

      # Configuration WordPress
      WORDPRESS_CONFIG_EXTRA: |
        # URLs du site
        define('WP_HOME', 'https://\${DOMAIN_NAME}');
        define('WP_SITEURL', 'https://\${DOMAIN_NAME}');

        # Configuration Redis
        define('WP_REDIS_HOST', 'redis_${site_name}');
        define('WP_REDIS_PORT', 6379);
        define('WP_REDIS_DATABASE', 0);
        define('WP_REDIS_PASSWORD', '\${REDIS_PASSWORD}');
        define('WP_REDIS_PREFIX', 'wp_');
        define('WP_REDIS_MAXTTL', 3600);
        define('WP_REDIS_TIMEOUT', 1);
        define('WP_REDIS_READ_TIMEOUT', 1);
        define('WP_CACHE', true);

        # Configuration du débogage
        define('WP_DEBUG_LOG', \${WP_DEBUG});
        define('WP_DEBUG_DISPLAY', \${WP_DEBUG});
        define('SCRIPT_DEBUG', \${WP_DEBUG});
        define('SAVEQUERIES', \${WP_DEBUG});

        # Limites de mémoire
        define('WP_MEMORY_LIMIT', '\${WP_MEMORY_LIMIT}');
        define('WP_MAX_MEMORY_LIMIT', '\${WP_MAX_MEMORY_LIMIT}');

        # Mises à jour et maintenance
        define('WP_AUTO_UPDATE_CORE', true);
        define('EMPTY_TRASH_DAYS', 7);
        define('WP_POST_REVISIONS', 5);

        # Sécurité
        define('DISALLOW_FILE_EDIT', true);

        # Chemins WordPress
        define('WP_PLUGIN_DIR', '/var/www/html/wp-content/plugins');
        define('WP_CONTENT_DIR', '/var/www/html/wp-content');
        define('WP_CONTENT_URL', 'https://\${DOMAIN_NAME}/wp-content');
        define('WP_LANG_DIR', '/var/www/html/wp-content/languages');

        # Configuration de la langue
        define('WPLANG', '\${WP_LANG}');
        define('WP_LOAD_TEXTDOMAIN_DEBUG', false);
  
    volumes:
      - wordpress_data_${site_name}:/var/www/html
    user: "33:33"  # www-data:www-data
    networks:
      - proxy
      - ${site_name}_network
    depends_on:
      mysql_${site_name}:
        condition: service_healthy
      redis_${site_name}:
        condition: service_started

    labels:
      # Activer Traefik pour ce service
      - "traefik.enable=true"

      # Route pour le domaine principal
      - "traefik.http.routers.wordpress-\${SITE_NAME}.rule=Host(\`\${DOMAIN_NAME}\`)"
      - "traefik.http.routers.wordpress-\${SITE_NAME}.entrypoints=websecure"
      - "traefik.http.routers.wordpress-\${SITE_NAME}.tls=true"
      - "traefik.http.routers.wordpress-\${SITE_NAME}.tls.certresolver=letsencrypt"
      - "traefik.http.services.wordpress-\${SITE_NAME}.loadbalancer.server.port=80"

      # Redirection de www vers non-www
      - "traefik.http.routers.wordpress-www-\${SITE_NAME}.rule=Host(\`www.\${DOMAIN_NAME}\`)"
      - "traefik.http.routers.wordpress-www-\${SITE_NAME}.entrypoints=websecure"
      - "traefik.http.routers.wordpress-www-\${SITE_NAME}.middlewares=redirect-to-non-www-\${SITE_NAME}"
      - "traefik.http.routers.wordpress-www-\${SITE_NAME}.tls=true"
      - "traefik.http.routers.wordpress-www-\${SITE_NAME}.tls.certresolver=letsencrypt"

      # Middleware pour la redirection
      - "traefik.http.middlewares.redirect-to-non-www-\${SITE_NAME}.redirectregex.regex=^https://www\\\\.(.*)"
      - "traefik.http.middlewares.redirect-to-non-www-\${SITE_NAME}.redirectregex.replacement=https://\$\${1}"
      - "traefik.http.middlewares.redirect-to-non-www-\${SITE_NAME}.redirectregex.permanent=true"

networks:
  proxy:  
    external: true 
  ${site_name}_network:
    driver: bridge  
  redis_network:
    driver: bridge  

volumes:
  wordpress_data_${site_name}:
    driver: local
  db_data_${site_name}: {}
  redis_data_${site_name}: {}
EOF
            ;;
        "laravel")
            # Configuration Laravel
            cat > docker-compose.yml << EOF
services:
  mysql_${site_name}:  
    image: mariadb:${mysql_version}
    container_name: mysql_${site_name}
    environment:
      - MYSQL_ROOT_PASSWORD=\${MYSQL_ROOT_PASSWORD}
      - MYSQL_DATABASE=\${MYSQL_DATABASE}
      - MYSQL_USER=\${MYSQL_USER}
      - MYSQL_PASSWORD=\${MYSQL_PASSWORD}
    volumes:
      - mysql_data:/var/lib/mysql
    networks:
      - proxy
      - ${site_name}_network

  redis_${site_name}:
    image: redis:${redis_version}
    restart: always
    container_name: redis_${site_name}
    command: redis-server --requirepass \${REDIS_PASSWORD}
    volumes:
      - redis_data:/data
    networks:
      - ${site_name}_network
      - proxy

  app_${site_name}:
    image: php:8.2-fpm
    container_name: app_${site_name}
    volumes:
      - ./src:/var/www/html
    networks:
      - proxy
      - ${site_name}_network
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.${site_name}.rule=Host(\`\${DOMAIN_NAME}\`)"
      - "traefik.http.routers.${site_name}.entrypoints=websecure"
      - "traefik.http.routers.${site_name}.tls=true"
      - "traefik.http.routers.${site_name}.tls.certresolver=letsencrypt"

networks:
  proxy:
    external: true
  ${site_name}_network:
    driver: bridge

volumes:
  mysql_data:
  redis_data:
EOF
            ;;
        *)
            error "Type d'application non supporté: $app_type"
            ;;
    esac
}

# Fonction pour générer le fichier .env en fonction du type d'application
generate_env_file() {
    local app_type=$1
    local site_name=$2
    local domain_name=$3
    local db_password=$4
    local redis_password=$5
    local mysql_root_password=$6

    case $app_type in
        "wordpress")
            cat > .env << EOF
# Configuration du site
SITE_NAME=${site_name}
DOMAIN_NAME=${domain_name}
WP_LANG=fr_FR
WP_SITE_TITLE="${site_name}"
WP_SITE_DESCRIPTION="Site WordPress de ${site_name}"

# Configuration MySQL
MYSQL_ROOT_PASSWORD=${mysql_root_password}
MYSQL_DATABASE=wordpress_${site_name}
MYSQL_USER=wordpress_${site_name}
MYSQL_PASSWORD=${db_password}
MYSQL_HOST=mysql_${site_name}

# Configuration Redis
REDIS_PASSWORD=${redis_password}
REDIS_HOST=redis_${site_name}

# Configuration WordPress
WP_DEBUG=false
WP_MEMORY_LIMIT=256M
WP_MAX_MEMORY_LIMIT=512M
WP_POST_MAX_SIZE=64M
WP_UPLOAD_MAX_FILESIZE=64M

# Configuration PHP
PHP_MEMORY_LIMIT=256M
PHP_MAX_EXECUTION_TIME=300
PHP_POST_MAX_SIZE=64M
PHP_UPLOAD_MAX_FILESIZE=64M
EOF
            ;;
        "laravel")
            cat > .env << EOF
# Configuration du site
SITE_NAME=${site_name}
DOMAIN_NAME=${domain_name}

# Configuration MySQL
MYSQL_ROOT_PASSWORD=${mysql_root_password}
MYSQL_DATABASE=laravel_${site_name}
MYSQL_USER=laravel_${site_name}
MYSQL_PASSWORD=${db_password}
MYSQL_HOST=mysql_${site_name}

# Configuration Redis
REDIS_PASSWORD=${redis_password}
REDIS_HOST=redis_${site_name}
EOF
            ;;
    esac
}

# Ajouter une option pour nettoyer les volumes
CLEAN_VOLUMES=false

# Parser les arguments
APP_TYPE=$DEFAULT_APP_TYPE
MYSQL_VERSION=$DEFAULT_MYSQL_VERSION
REDIS_VERSION=$DEFAULT_REDIS_VERSION
WP_VERSION=$DEFAULT_WORDPRESS_VERSION
WORDPRESS_IMAGE=$DEFAULT_WORDPRESS_IMAGE

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--type)
            APP_TYPE="$2"
            shift 2
            ;;
        -m|--mysql)
            MYSQL_VERSION="$2"
            shift 2
            ;;
        -r|--redis)
            REDIS_VERSION="$2"
            shift 2
            ;;
        -w|--wp)
            WP_VERSION="$2"
            shift 2
            ;;
        -i|--wp-image)
            WORDPRESS_IMAGE="$2"
            shift 2
            ;;
        --clean)
            CLEAN_VOLUMES=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            if [ -z "$SITE_NAME" ]; then
                SITE_NAME="$1"
            elif [ -z "$DOMAIN_NAME" ]; then
                DOMAIN_NAME="$1"
            else
                error "Argument inconnu: $1"
            fi
            shift
            ;;
    esac
done

# Vérifier les arguments requis
if [ -z "$SITE_NAME" ] || [ -z "$DOMAIN_NAME" ]; then
    show_help
    error "Le nom du site et le domaine sont requis"
fi

# Partie principale du script
init_log

# Vérifier les prérequis
check_docker
check_docker_compose

# Vérifier le domaine
check_domain

# Créer la structure du site
create_site_structure

# Générer les fichiers de configuration
generate_config_files

# Vérifier l'espace disque
check_disk_space

# Démarrer les services
start_services

# Vérifier les volumes Docker
check_docker_volumes

# Vérifier les certificats SSL
check_ssl_certificates

# Vérifier la santé du site
check_site_health

# Créer une sauvegarde
create_backup

# Vérifier les mises à jour WordPress
check_wordpress_updates

# Vérifier les logs
check_logs

# Vérifier l'accessibilité du site
check_site_accessibility

# Afficher le résumé
show_summary

# Vérifier les dépendances système
check_system_dependencies

# Configurer les sauvegardes automatiques
setup_auto_backups

# Configurer la surveillance
setup_monitoring

# Configurer les mises à jour automatiques
setup_auto_updates

# Configurer la sécurité
setup_security

success "Déploiement terminé avec succès !"

# ./deploy.sh blog blog.digitaleflex.com