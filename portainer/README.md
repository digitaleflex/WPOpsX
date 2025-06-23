# Portainer – Interface de gestion Docker

## Présentation

Portainer fournit une interface web moderne et sécurisée pour gérer vos conteneurs, stacks, volumes et réseaux Docker.

---

## Installation rapide

1. Copiez le fichier `.env.example` en `.env` et personnalisez la variable :
   - `DOMAIN_NAME` : domaine principal utilisé pour accéder à Portainer via Traefik

   ```bash
   cp .env.example .env
   # puis éditez .env
   ```

2. Lancez Portainer :
   ```bash
   docker-compose up -d
   ```

3. Accédez à l'interface :
   - https://portainer.${DOMAIN_NAME}

---

## Variable d'environnement

- `DOMAIN_NAME` : domaine utilisé pour le routage Traefik (exemple : moninfra.com)

--- 