#!/bin/bash

# Chemin vers le dossier WordPress
WORDPRESS_DIR="/home/audest/my_arch/wordpress"
TRAEFIK_CONFIG="/home/audest/my_arch/traefik/traefik.yml"

# Fonction pour extraire les domaines uniques
extract_domains() {
    # Trouver tous les .env dans les dossiers WordPress
    find "$WORDPRESS_DIR" -name ".env" -type f | while read -r env_file; do
        # Extraire le domaine du fichier .env
        domain=$(grep "DOMAIN_NAME=" "$env_file" | cut -d'=' -f2)
        if [ ! -z "$domain" ]; then
            # Extraire le domaine principal (sans le sous-domaine)
            main_domain=$(echo "$domain" | sed -E 's/^[^.]+\.(.+)$/\1/')
            echo "$main_domain"
        fi
    done | sort -u
}

# Créer la nouvelle configuration des domaines
generate_domains_config() {
    echo "      tls:"
    echo "        certResolver: letsencrypt"
    echo "        domains:"
    
    # Pour chaque domaine unique
    extract_domains | while read -r main_domain; do
        echo "          - main: \"$main_domain\""
        echo "            sans:"
        echo "              - \"*.$main_domain\""
    done
}

# Sauvegarder l'ancienne configuration
cp "$TRAEFIK_CONFIG" "${TRAEFIK_CONFIG}.bak"

# Mettre à jour la configuration
awk -v domains="$(generate_domains_config)" '
    /tls:/ { 
        print domains
        skip=1
        next
    }
    /domains:/ { 
        skip=1
        next
    }
    /- main:/ { 
        if (skip) {
            skip=0
            next
        }
    }
    !skip { 
        print
    }
' "$TRAEFIK_CONFIG" > "${TRAEFIK_CONFIG}.new"

# Remplacer l'ancienne configuration par la nouvelle
mv "${TRAEFIK_CONFIG}.new" "$TRAEFIK_CONFIG"

# Redémarrer Traefik
cd /home/audest/my_arch/traefik && sudo docker-compose down && sudo docker-compose up -d

echo "Configuration des domaines mise à jour et Traefik redémarré." 