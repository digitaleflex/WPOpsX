#!/usr/bin/env bash
# =============================================================================
# WPOpsX — Initialisation de l'hôte (idempotent, relançable sans risque)
# -----------------------------------------------------------------------------
#   ./scripts/init.sh
#
# Crée les prérequis communs à tous les modules :
#   1. le réseau Docker externe `proxy` (requis par traefik/monitoring/portainer/sites)
#   2. le fichier de stockage ACME `traefik/acme.json` (mode 600)
#   3. les fichiers `.env` des modules, depuis les `.env.example`
#   4. la validation de toutes les configurations (compose, YAML, scripts)
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROXY_NETWORK="${PROXY_NETWORK:-proxy}"
ACME_FILE="${REPO_ROOT}/traefik/acme.json"
MODULES=(traefik monitoring portainer)

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
ok()   { printf "${GREEN}[ OK ]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
die()  { printf "${RED}[FAIL]${NC} %s\n" "$*" >&2; exit 1; }

# --- 0. Docker ---------------------------------------------------------------
command -v docker >/dev/null 2>&1 || die "docker est introuvable dans le PATH"
docker info >/dev/null 2>&1 || die "le démon Docker n'est pas démarré / accessible"
ok "docker disponible"

# --- 1. Réseau externe partagé ----------------------------------------------
if docker network inspect "$PROXY_NETWORK" >/dev/null 2>&1; then
    ok "réseau Docker '${PROXY_NETWORK}' déjà présent"
else
    docker network create "$PROXY_NETWORK" >/dev/null
    ok "réseau Docker '${PROXY_NETWORK}' créé"
fi

# --- 2. Stockage ACME --------------------------------------------------------
# Doit exister AVANT le premier démarrage de Traefik : sinon Docker crée un
# RÉPERTOIRE à l'emplacement du bind-mount et Traefik ne peut plus écrire ses
# certificats (l'erreur n'apparaît que dans les logs, de façon asynchrone).
if [ ! -f "$ACME_FILE" ]; then
    if [ -e "$ACME_FILE" ]; then
        die "${ACME_FILE} existe mais n'est pas un fichier (Docker a probablement créé un dossier) : supprimez-le puis relancez"
    fi
    : > "$ACME_FILE"
    ok "traefik/acme.json créé"
fi
chmod 600 "$ACME_FILE"
ok "traefik/acme.json : permissions 600 (clés privées des certificats non lisibles par les autres comptes)"

# --- 3. Fichiers .env -------------------------------------------------------
for module in "${MODULES[@]}"; do
    env_file="${REPO_ROOT}/${module}/.env"
    example_file="${REPO_ROOT}/${module}/.env.example"
    if [ -f "$env_file" ]; then
        chmod 600 "$env_file"
        ok "${module}/.env déjà présent"
    elif [ -f "$example_file" ]; then
        cp "$example_file" "$env_file"
        chmod 600 "$env_file"
        warn "${module}/.env créé depuis .env.example — À PERSONNALISER avant de démarrer"
    else
        warn "aucun .env ni .env.example pour le module ${module}"
    fi
done

# --- 4. Validation ----------------------------------------------------------
info "validation des configurations Docker Compose..."
compose_failed=0
while IFS= read -r compose_file; do
    dir="$(dirname "$compose_file")"
    # Le template WordPress contient des ${VARS} destinées à être interpolées
    # depuis le .env du site : on valide avec un jeu de variables de test.
    if ! (
        cd "$dir"
        if [ -f .env ]; then
            docker compose -f "$compose_file" config -q
        else
            DOMAIN_NAME=exemple.com SITE_NAME=exemple \
            MYSQL_ROOT_PASSWORD=x MYSQL_DATABASE=x MYSQL_USER=x MYSQL_PASSWORD=x \
            MYSQL_HOST=x REDIS_PASSWORD=x WP_LANG=fr_FR WP_DEBUG=false \
            WP_MEMORY_LIMIT=256M WP_MAX_MEMORY_LIMIT=512M \
            WP_POST_MAX_SIZE=64M WP_UPLOAD_MAX_FILESIZE=64M \
            docker compose -f "$compose_file" config -q
        fi
    ); then
        warn "${compose_file#${REPO_ROOT}/} : configuration invalide (voir ci-dessus)"
        compose_failed=1
    else
        ok "${compose_file#${REPO_ROOT}/} valide"
    fi
done < <(find "$REPO_ROOT" -name 'docker-compose.yml' -not -path '*/.git/*')
[ "$compose_failed" -eq 0 ] || die "au moins une configuration compose est invalide"

# --- Résumé -----------------------------------------------------------------
printf '\n'
ok "initialisation terminée"
printf '  1. personnaliser les .env : %s\n' "${MODULES[*]/%//.env}"
printf '  2. démarrer le reverse proxy : (cd traefik && docker compose up -d)\n'
printf '  3. déployer un site : (cd wordpress/template && ./deploy.sh monsite monsite.example.com)\n'
