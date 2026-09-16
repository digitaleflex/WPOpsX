#!/usr/bin/env bash
# =============================================================================
# WPOpsX — Déploiement d'un site WordPress
# -----------------------------------------------------------------------------
#   ./deploy.sh <nom_du_site> <domaine>
#
# Exemple :
#   ./deploy.sh sainteadoration sainteadoration.org
#
# Options :
#   -m, --mysql VERSION     version de MariaDB          (défaut : 10.11)
#   -r, --redis VERSION     version de Redis            (défaut : 7-alpine)
#   -i, --wp-image IMAGE    image WordPress             (défaut : eflexcloud/wordpress-custom)
#   --lite                  accepté pour compatibilité (le déploiement d'un site
#                           n'installe jamais monitoring/portainer : ils se
#                           déploient depuis leurs propres dossiers)
#   --clean                 SUPPRIME les volumes existants du site (données !)
#   -y, --yes               ne pas demander confirmation pour --clean
#   --no-cron               ne pas installer les tâches cron backup/update
#   -h, --help              cette aide
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SITES_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_TEMPLATE="${SCRIPT_DIR}/docker-compose.yml"
ENV_TEMPLATE="${SCRIPT_DIR}/.env.example"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
STEP=0
TOTAL_STEPS=13
DEPLOY_LOG="${SCRIPT_DIR}/deployment.log"

info() { printf "${BLUE}[INFO]${NC} %s\n" "$*"; log_line "[INFO] $*"; }
ok()   { printf "${GREEN}[ OK ]${NC} %s\n" "$*"; log_line "[ OK ] $*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*" >&2; log_line "[WARN] $*"; }
die()  { printf "${RED}[FAIL]${NC} %s\n" "$*" >&2; log_line "[FAIL] $*"; exit 1; }

log_line() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$DEPLOY_LOG"; }

# Progression : le compteur est dérivé du nombre réel d'étapes (TOTAL_STEPS),
# chaque étape affiche [n/N] — plus de barre à 150 %.
step() {
    STEP=$((STEP + 1))
    if [ "$STEP" -gt "$TOTAL_STEPS" ]; then
        TOTAL_STEPS="$STEP"
    fi
    printf "\n${BLUE}== [%d/%d] %s${NC}\n" "$STEP" "$TOTAL_STEPS" "$1"
    log_line "== [$STEP/$TOTAL_STEPS] $1"
}

show_help() {
    sed -n '3,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

usage_error() { printf "${RED}%s${NC}\n\n" "$1" >&2; show_help; exit 1; }

# --- Arguments ---------------------------------------------------------------
APP_TYPE="wordpress"
MYSQL_VERSION="10.11"
REDIS_VERSION="7-alpine"
WORDPRESS_IMAGE="eflexcloud/wordpress-custom"
CLEAN_VOLUMES=false
ASSUME_YES=false
INSTALL_CRON=true
SITE_NAME=""
DOMAIN_NAME=""

while [ $# -gt 0 ]; do
    case "$1" in
        -t|--type)        APP_TYPE="${2:-}"; shift 2 ;;
        -m|--mysql)       MYSQL_VERSION="${2:-}"; shift 2 ;;
        -r|--redis)       REDIS_VERSION="${2:-}"; shift 2 ;;
        -i|--wp-image)    WORDPRESS_IMAGE="${2:-}"; shift 2 ;;
        -w|--wp)          shift 2 ;;   # accepté mais sans effet (image imposée)
        --lite)           shift ;;
        --clean)          CLEAN_VOLUMES=true; shift ;;
        -y|--yes)         ASSUME_YES=true; shift ;;
        --no-cron)        INSTALL_CRON=false; shift ;;
        -h|--help)        show_help; exit 0 ;;
        -*)               usage_error "Option inconnue : $1" ;;
        *)
            if [ -z "$SITE_NAME" ]; then SITE_NAME="$1"
            elif [ -z "$DOMAIN_NAME" ]; then DOMAIN_NAME="$1"
            else usage_error "Argument inconnu : $1"
            fi
            shift ;;
    esac
done

[ -n "$SITE_NAME" ] && [ -n "$DOMAIN_NAME" ] || usage_error "Le nom du site et le domaine sont requis"

if [ "$APP_TYPE" != "wordpress" ]; then
    die "Type '${APP_TYPE}' non pris en charge : seul 'wordpress' est déployable aujourd'hui (voir coming_soon.md pour Laravel)."
fi
if ! printf '%s' "$SITE_NAME" | grep -Eq '^[a-z0-9]([a-z0-9_-]*[a-z0-9])?$'; then
    die "Nom de site invalide : minuscules, chiffres, '-' et '_' uniquement (ex: mon-site)"
fi

SITE_DIR="${SITES_DIR}/${SITE_NAME}"
DB_NAME="wordpress_$(printf '%s' "$SITE_NAME" | tr -- '-' '_')"
DB_USER="$DB_NAME"

# --- Aides -------------------------------------------------------------------
require_docker() {
    command -v docker >/dev/null 2>&1 || die "docker est introuvable dans le PATH"
    docker info >/dev/null 2>&1 || die "le démon Docker n'est pas démarré ou accessible"
    docker compose version >/dev/null 2>&1 || die "le plugin 'docker compose' (v2) est requis. docker-compose v1 est EOL depuis 2023 : la commande est 'docker compose', pas 'docker-compose'."
}

random_secret() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 32
    else
        od -An -tx1 -N32 /dev/urandom | tr -d ' \n'
    fi
}

set_env_var() {
    # Remplacement sûr : valeurs hexadécimales uniquement, délimiteur '|'.
    local key="$1" value="$2" file="$3"
    if grep -q "^${key}=" "$file"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    else
        printf '%s=%s\n' "$key" "$value" >> "$file"
    fi
}

# =============================================================================
step "Vérification des prérequis"
require_docker
[ -f "$COMPOSE_TEMPLATE" ] || die "template introuvable : $COMPOSE_TEMPLATE"
[ -f "$ENV_TEMPLATE" ] || die "template d'environnement introuvable : $ENV_TEMPLATE"
docker network inspect proxy >/dev/null 2>&1 || die "le réseau Docker 'proxy' n'existe pas. Lancez d'abord : ./scripts/init.sh"
ok "docker + réseau 'proxy' disponibles"

step "Validation du domaine"
printf '%s' "$DOMAIN_NAME" | grep -Eq '^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)+$' \
    || die "Domaine invalide : $DOMAIN_NAME"
ok "domaine $DOMAIN_NAME valide"

step "Vérification de l'espace disque"
available_kb=$(df -Pk "$SITES_DIR" | awk 'NR==2 {print $4}')
if [ "${available_kb:-0}" -lt 5242880 ]; then
    warn "moins de 5 Go disponibles ($((available_kb / 1024)) Mo) : le déploiement peut échouer"
else
    ok "$((available_kb / 1024 / 1024)) Go disponibles"
fi

step "Préparation du dossier du site"
if [ -d "$SITE_DIR" ] && [ "$CLEAN_VOLUMES" = false ]; then
    warn "$SITE_DIR existe déjà — les données existantes seront CONSERVÉES"
    warn "pour repartir de zéro (destructif) : $0 --clean $SITE_NAME $DOMAIN_NAME"
fi
mkdir -p "$SITE_DIR"
ok "$SITE_DIR prêt"

step "Génération de la configuration (.env, secrets)"
if [ -f "${SITE_DIR}/.env" ] && [ "$CLEAN_VOLUMES" = false ]; then
    ok ".env existant conservé (mots de passe inchangés)"
else
    cp "$ENV_TEMPLATE" "${SITE_DIR}/.env"
    set_env_var SITE_NAME "$SITE_NAME" "${SITE_DIR}/.env"
    set_env_var DOMAIN_NAME "$DOMAIN_NAME" "${SITE_DIR}/.env"
    set_env_var MYSQL_DATABASE "$DB_NAME" "${SITE_DIR}/.env"
    set_env_var MYSQL_USER "$DB_USER" "${SITE_DIR}/.env"
    set_env_var MYSQL_ROOT_PASSWORD "$(random_secret)" "${SITE_DIR}/.env"
    set_env_var MYSQL_PASSWORD "$(random_secret)" "${SITE_DIR}/.env"
    set_env_var REDIS_PASSWORD "$(random_secret)" "${SITE_DIR}/.env"
    set_env_var MYSQL_VERSION "$MYSQL_VERSION" "${SITE_DIR}/.env"
    set_env_var REDIS_VERSION "$REDIS_VERSION" "${SITE_DIR}/.env"
    set_env_var WORDPRESS_IMAGE "$WORDPRESS_IMAGE" "${SITE_DIR}/.env"
    ok "secrets générés (openssl rand -hex 32)"
fi
# Le .env contient les mots de passe de la base et de Redis.
chmod 600 "${SITE_DIR}/.env"
ok "permissions de .env : 600"

step "Installation du fichier compose"
cp "$COMPOSE_TEMPLATE" "${SITE_DIR}/docker-compose.yml"
cp "${SCRIPT_DIR}/backup.sh" "${SITE_DIR}/backup.sh"
cp "${SCRIPT_DIR}/update.sh" "${SITE_DIR}/update.sh"
chmod +x "${SITE_DIR}/backup.sh" "${SITE_DIR}/update.sh"
mkdir -p "${SITE_DIR}/backups"
ok "docker-compose.yml + backup.sh + update.sh installés"

step "Validation de la configuration"
( cd "$SITE_DIR" && docker compose config -q ) || die "configuration invalide (voir l'erreur ci-dessus)"
ok "configuration compose valide"

if [ "$CLEAN_VOLUMES" = true ]; then
    step "Suppression des volumes existants (--clean)"
    warn "opération DESTRUCTIVE : base de données et fichiers de ${SITE_NAME} vont être supprimés"
    if [ "$ASSUME_YES" != true ]; then
        printf "Tapez le nom du site ('%s') pour confirmer : " "$SITE_NAME"
        read -r confirmation
        [ "$confirmation" = "$SITE_NAME" ] || die "confirmation incorrecte — rien n'a été supprimé"
    fi
    ( cd "$SITE_DIR" && docker compose down --remove-orphans --volumes ) || warn "échec partiel du nettoyage"
    ok "volumes supprimés"
else
    step "Nettoyage (sans suppression de données)"
    ( cd "$SITE_DIR" && docker compose down --remove-orphans 2>/dev/null ) || true
    ok "conteneurs précédents arrêtés (volumes conservés)"
fi

step "Démarrage des services"
( cd "$SITE_DIR" && docker compose up -d ) || die "échec du démarrage (voir : cd $SITE_DIR && docker compose logs)"
ok "conteneurs créés"

step "Attente de la base de données"
max_retries=30; retry=0; db_ready=false
while [ "$retry" -lt "$max_retries" ]; do
    if ( cd "$SITE_DIR" && docker compose exec -T mysql healthcheck.sh --connect --innodb_initialized ) >/dev/null 2>&1; then
        db_ready=true; break
    fi
    retry=$((retry + 1)); printf '.'; sleep 3
done
printf '\n'
[ "$db_ready" = true ] || die "la base n'est pas prête après $((max_retries * 3)) s. Diagnostic : cd $SITE_DIR && docker compose logs mysql"
ok "base de données prête"

step "Contrôle HTTP et certificat"
max_retries=20; retry=0; http_code=""
while [ "$retry" -lt "$max_retries" ]; do
    http_code=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "https://${DOMAIN_NAME}/" || true)
    case "$http_code" in
        200|301|302|403) break ;;
    esac
    retry=$((retry + 1)); printf '.'; sleep 6
done
printf '\n'
case "$http_code" in
    200) ok "https://${DOMAIN_NAME} répond 200" ;;
    301|302) ok "https://${DOMAIN_NAME} répond ${http_code} (redirection)" ;;
    403) warn "https://${DOMAIN_NAME} répond 403 (permissions ou règle applicative)" ;;
    *)   warn "pas de réponse HTTP exploitable (dernier code : '${http_code:-aucun}'). Le certificat TLS peut prendre quelques minutes ; sinon :" ;
         warn "  DNS de ${DOMAIN_NAME} -> IP du VPS ?  |  cd $SITE_DIR && docker compose logs wordpress" ;;
esac

if [ "$INSTALL_CRON" = true ]; then
    step "Installation des tâches cron (backup quotidien, mises à jour hebdomadaires)"
    cron_backup="0 2 * * * cd ${SITE_DIR} && ./backup.sh >> ${SITE_DIR}/backups/cron.log 2>&1 # wpopsx:${SITE_NAME}"
    cron_update="0 3 * * 0 cd ${SITE_DIR} && ./update.sh >> ${SITE_DIR}/backups/cron.log 2>&1 # wpopsx:${SITE_NAME}"
    if crontab -l 2>/dev/null | grep -qF "# wpopsx:${SITE_NAME}"; then
        ok "tâches déjà présentes pour ${SITE_NAME}"
    else
        ( crontab -l 2>/dev/null | grep -vF "# wpopsx:${SITE_NAME}" || true
          printf '%s\n%s\n' "$cron_backup" "$cron_update" ) | crontab - \
            || warn "installation du cron impossible (crontab non disponible ?)"
        ok "cron installé : backup 02h00, mises à jour dimanche 03h00"
    fi
else
    step "Tâches cron ignorées (--no-cron)"
fi

# =============================================================================
step "Résumé"
cat <<EOF

  Site         : ${SITE_NAME}
  URL          : https://${DOMAIN_NAME}
  Dossier      : ${SITE_DIR}
  Base         : ${DB_NAME} (utilisateur ${DB_USER})
  Identifiants : ${SITE_DIR}/.env (chmod 600)

  Commandes utiles :
    cd ${SITE_DIR} && docker compose ps
    cd ${SITE_DIR} && docker compose logs -f wordpress
    cd ${SITE_DIR} && ./backup.sh          # sauvegarde manuelle
    cd ${SITE_DIR} && ./update.sh          # mises à jour WP/plugins

  Logs : ${DEPLOY_LOG}
EOF
ok "déploiement terminé"
