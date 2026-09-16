#!/usr/bin/env bash
# =============================================================================
# WPOpsX — Porte de vérification (le "gate" du dépôt)
# -----------------------------------------------------------------------------
#   ./scripts/verify.sh          # tout : YAML, Bash, compose, config Traefik
#   ./scripts/verify.sh --fast   # sans Docker (YAML + Bash uniquement)
#
# Toute correction doit passer ce script AVANT commit : un fichier qui « a
# l'air bon » n'est pas un fichier qui fonctionne.
# =============================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 2

FAST=false
[ "${1:-}" = "--fast" ] && FAST=true

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
FAILED=0
SKIPPED=0

section() { printf "\n${BLUE}== %s${NC}\n" "$1"; }
pass()    { printf "${GREEN}[ OK ]${NC} %s\n" "$1"; }
fail()    { printf "${RED}[FAIL]${NC} %s\n" "$1"; FAILED=$((FAILED + 1)); }
skip()    { printf "${YELLOW}[SKIP]${NC} %s\n" "$1"; SKIPPED=$((SKIPPED + 1)); }

# --- 1. YAML -----------------------------------------------------------------
section "YAML (yamllint, erreurs uniquement)"
if command -v yamllint >/dev/null 2>&1; then
    YAMLLINT=yamllint
elif python -m yamllint --version >/dev/null 2>&1; then
    YAMLLINT="python -m yamllint"
else
    YAMLLINT=""
fi
if [ -z "$YAMLLINT" ]; then
    skip "yamllint absent (pip install yamllint)"
elif $YAMLLINT --no-warnings . ; then
    pass "tous les fichiers YAML sont valides"
else
    fail "yamllint a signalé des erreurs"
fi

# --- 2. Bash -----------------------------------------------------------------
section "Scripts Bash (shellcheck, erreurs uniquement)"
# L'outil shellcheck est soit dans le PATH, soit installé par le paquet Python
# `shellcheck-py` (pip install shellcheck-py) dans le dossier Scripts de Python.
SHELLCHECK=""
if command -v shellcheck >/dev/null 2>&1; then
    SHELLCHECK="shellcheck"
else
    py_scripts="$(python -c 'import sysconfig; print(sysconfig.get_path("scripts"))' 2>/dev/null || true)"
    for candidate in "${py_scripts}/shellcheck" "${py_scripts}/shellcheck.exe"; do
        if [ -n "$py_scripts" ] && [ -x "$candidate" ]; then
            SHELLCHECK="$candidate"
            break
        fi
    done
fi
if [ -z "$SHELLCHECK" ]; then
    skip "shellcheck absent (apt install shellcheck, ou pip install shellcheck-py)"
else
    mapfile -t sh_files < <(find . -name '*.sh' -not -path './.git/*')
    if "$SHELLCHECK" -S warning "${sh_files[@]}"; then
        pass "${#sh_files[@]} scripts sans erreur"
    else
        fail "shellcheck a signalé des erreurs"
    fi
fi

# --- 3. Syntaxe Bash ---------------------------------------------------------
section "Syntaxe Bash (bash -n)"
syn_ok=true
for f in scripts/*.sh traefik/*.sh wordpress/template/*.sh; do
    [ -f "$f" ] || continue
    bash -n "$f" || { fail "syntaxe invalide : $f"; syn_ok=false; }
done
$syn_ok && pass "tous les scripts sont syntaxiquement valides"

# --- 4. Bits exécutables -----------------------------------------------------
# Un script en mode 100644 se lance sans problème sous Windows (où le bit est
# ignoré) mais échoue sur un serveur Linux : « ./deploy.sh: Permission denied ».
# Seul le mode enregistré dans Git compte pour les clones.
section "Bits exécutables des scripts (mode Git 100755)"
if ! git rev-parse --git-dir >/dev/null 2>&1; then
    skip "pas un dépôt Git"
else
    not_exec="$(git ls-files -s '*.sh' | awk '$1 != "100755" {print $4}')"
    if [ -z "$not_exec" ]; then
        pass "tous les scripts sont exécutables"
    else
        fail "scripts non exécutables (./script.sh échouerait sur Linux) :"
        printf '       %s\n' $not_exec
        printf '       correction : git update-index --chmod=+x %s\n' $not_exec
    fi
fi

if [ "$FAST" = true ]; then
    printf "\n${YELLOW}--fast : étapes Docker ignorées${NC}\n"
else
    # --- 5. Docker Compose ----------------------------------------------------
    section "Configurations Docker Compose (docker compose config -q)"
    if ! docker compose version >/dev/null 2>&1; then
        skip "docker compose indisponible"
    elif ! docker info >/dev/null 2>&1; then
        skip "démon Docker arrêté"
    else
        while IFS= read -r compose_file; do
            dir="$(dirname "$compose_file")"
            # Chemin absolu : le `cd` ci-dessous casserait un chemin relatif.
            abs_compose="$(cd "$dir" && pwd)/$(basename "$compose_file")"
            # Les modules exigent un .env : on valide contre .env.example pour
            # ne pas modifier le dépôt et détecter les ${VAR} non documentées.
            generated_env=false
            if [ ! -f "${dir}/.env" ] && [ -f "${dir}/.env.example" ]; then
                cp "${dir}/.env.example" "${dir}/.env"
                generated_env=true
            fi
            if ( cd "$dir" && docker compose -f "$abs_compose" config -q ) 2>/dev/null; then
                pass "${compose_file#./}"
            else
                fail "${compose_file#./} : configuration invalide"
                ( cd "$dir" && docker compose -f "$abs_compose" config ) 2>&1 | head -5
            fi
            $generated_env && rm -f "${dir}/.env"
        done < <(find . -name 'docker-compose.yml' -not -path './.git/*')
    fi

    # --- 6. Configuration Traefik (chargement réel) ---------------------------
    section "Chargement réel de la configuration Traefik"
    if ! docker compose version >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
        skip "docker indisponible"
    else
        tmp="$(mktemp -d)"
        # Traefik lit /etc/traefik/traefik.yml par défaut : on teste le fichier
        # ET le dossier dynamique dans les conditions du déploiement.
        cp traefik/traefik.yml "$tmp/traefik.yml"
        mkdir -p "$tmp/dynamic"
        cp traefik/dynamic/*.yml "$tmp/dynamic/" 2>/dev/null || true
        printf '{}' > "$tmp/acme.json"
        # Les ports 80/443 sont souvent pris : on décale les entryPoints pour
        # ne pas toucher aux conteneurs en production.
        sed -i 's/address: ":80"/address: ":18080"/; s/address: ":443"/address: ":18443"/; s/address: ":8082"/address: ":18082"/' "$tmp/traefik.yml"
        docker rm -f wpopsx-config-check >/dev/null 2>&1 || true
        if docker run -d --name wpopsx-config-check \
                -v "${tmp}:/etc/traefik" \
                -v "${tmp}/acme.json:/etc/traefik/acme.json" \
                traefik:v3.7.13 >/dev/null 2>&1; then
            sleep 6
            logs="$(docker logs wpopsx-config-check 2>&1 | sed 's/\x1b\[[0-9;]*m//g')"
            if printf '%s' "$logs" | grep -qiE "field not found|cannot unmarshal|configuration error|panic"; then
                fail "Traefik rejette la configuration :"
                printf '%s\n' "$logs" | grep -iE "field not found|cannot unmarshal|configuration error|panic" | head -5
            else
                pass "Traefik charge traefik.yml + dynamic/ sans erreur"
            fi
            docker rm -f wpopsx-config-check >/dev/null 2>&1 || true
        else
            skip "impossible de lancer le conteneur de test (image traefik:v3.7.13 absente ?)"
        fi
        rm -rf "$tmp"
    fi
fi

# --- Résumé ------------------------------------------------------------------
printf '\n%s\n' "----------------------------------------------------------------"
if [ "$FAILED" -eq 0 ]; then
    printf "${GREEN}Vérification réussie${NC} (%d étape(s) ignorée(s))\n" "$SKIPPED"
    exit 0
fi
printf "${RED}%d vérification(s) en échec${NC} (%d ignorée(s))\n" "$FAILED" "$SKIPPED"
exit 1
