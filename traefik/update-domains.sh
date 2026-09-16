#!/usr/bin/env bash
# =============================================================================
# WPOpsX — Inventaire et contrôle des domaines déclarés
# -----------------------------------------------------------------------------
#   ./update-domains.sh [chemin_des_sites]
#
# ⚠️ CE SCRIPT N'ÉCRIT PLUS DANS traefik.yml.
# La version précédente réécrivait la configuration statique avec awk : elle
# pouvait corrompre le fichier (suppression de lignes au hasard dans les
# sections `tls:`), ne validait rien, puis redémarrait Traefik — coupant tous
# les sites. Elle est devenue inutile : Traefik découvre les domaines tout seul
# grâce aux labels Docker des sites (providers.docker.watch) et émet les
# certificats via le `certResolver` par défaut de l'entryPoint websecure.
#
# Ce script fait désormais un contrôle en LECTURE SEULE :
#   1. liste les sites déployés et leurs domaines (lecture des .env)
#   2. indique pour chaque domaine si un certificat existe dans acme.json
#   3. vérifie que chaque domaine répond bien en HTTPS
# Code retour 1 si au moins un domaine n'a pas de certificat.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SITES_ROOT="${1:-${SITES_ROOT:-${REPO_ROOT}/wordpress}}"
ACME_FILE="${ACME_FILE:-${SCRIPT_DIR}/acme.json}"
TIMEOUT_HTTP="${TIMEOUT_HTTP:-10}"

[ -d "$SITES_ROOT" ] || { printf "Répertoire des sites introuvable : %s\n" "$SITES_ROOT" >&2; exit 2; }

# --- 1. Inventaire -----------------------------------------------------------
# Le .env d'un site contient DOMAIN_NAME=<domaine> ; le dossier "template" est
# ignoré (son .env.example contient un domaine d'exemple).
declare -a SITES=() DOMAINS=()
while IFS= read -r env_file; do
    site_dir="$(dirname "$env_file")"
    site_name="$(basename "$site_dir")"
    [ "$site_name" = "template" ] && continue
    domain="$(grep -E '^[[:space:]]*DOMAIN_NAME=' "$env_file" | head -n1 | cut -d= -f2- | tr -d '"'"'"' ' | tr -d '\r')"
    [ -n "$domain" ] || continue
    SITES+=("$site_name")
    DOMAINS+=("$domain")
done < <(find "$SITES_ROOT" -mindepth 2 -maxdepth 2 -name '.env' -type f | sort)

if [ "${#DOMAINS[@]}" -eq 0 ]; then
    printf "Aucun site trouvé sous %s (aucun .env avec DOMAIN_NAME).\n" "$SITES_ROOT"
    exit 0
fi

printf 'Sites déployés : %d\n\n' "${#DOMAINS[@]}"
printf '%-24s %-38s %-12s %s\n' "SITE" "DOMAINE" "CERTIFICAT" "HTTPS"
printf '%s\n' "------------------------------------------------------------------------------------------"

cert_count=0
missing_cert=0
unreachable=0

for i in "${!DOMAINS[@]}"; do
    site="${SITES[$i]}"
    domain="${DOMAINS[$i]}"

    # --- 2. Présence du certificat dans acme.json ---------------------------
    cert_status="acme.json absent"
    if [ -f "$ACME_FILE" ]; then
        if command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
            py="$(command -v python3 || command -v python)"
            if "$py" - "$ACME_FILE" "$domain" <<'PY' >/dev/null 2>&1
import json, sys
acme, domain = sys.argv[1], sys.argv[2]
try:
    data = json.load(open(acme))
except Exception:
    sys.exit(1)
for resolver in data.values():
    for cert in (resolver.get("Certificates") or []):
        names = [cert.get("domain", {}).get("main")] + list(cert.get("domain", {}).get("sans") or [])
        if domain in names:
            sys.exit(0)
sys.exit(1)
PY
            then
                cert_status="present"; cert_count=$((cert_count + 1))
            else
                cert_status="ABSENT"; missing_cert=$((missing_cert + 1))
            fi
        else
            cert_status="python absent"
        fi
    fi

    # --- 3. Réponse HTTPS ---------------------------------------------------
    http_code="$(curl -s -o /dev/null -m "$TIMEOUT_HTTP" -w '%{http_code}' "https://${domain}/" 2>/dev/null || true)"
    case "$http_code" in
        200|301|302|403) http_status="OK (${http_code})" ;;
        "")              http_status="injoignable"; unreachable=$((unreachable + 1)) ;;
        *)               http_status="code ${http_code}"; unreachable=$((unreachable + 1)) ;;
    esac

    printf '%-24s %-38s %-12s %s\n' "$site" "$domain" "$cert_status" "$http_status"
done

printf '\nCertificats trouvés : %d/%d | sans certificat : %d | HTTPS non validé : %d\n' \
    "$cert_count" "${#DOMAINS[@]}" "$missing_cert" "$unreachable"

if [ "$missing_cert" -gt 0 ] || [ "$unreachable" -gt 0 ]; then
    printf '\nPistes :\n'
    printf '  - DNS du domaine pointe-t-il vers ce serveur ?\n'
    printf '  - Le router existe-t-il ?  docker exec traefik traefik healthcheck --ping  puis l API/dashboard\n'
    printf '  - Les erreurs ACME :  docker logs traefik 2>&1 | grep -i acme\n'
    exit 1
fi

printf '\nTous les domaines déclarés sont couverts par un certificat et répondent.\n'
