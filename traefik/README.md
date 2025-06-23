# Traefik Standardisé – Reverse Proxy Docker prêt à l’emploi

## Sommaire
- [Présentation](#présentation)
- [Prérequis](#prérequis)
- [Installation rapide](#installation-rapide)
- [Personnalisation & .env](#personnalisation--env)
- [Générer un mot de passe hashé](#générer-un-mot-de-passe-hashé)
- [Exemples d’intégration](#exemples-dintégration)
- [Sécurité](#sécurité)
- [Maintenance](#maintenance)
- [FAQ / Dépannage](#faq--dépannage)
- [Support & contribution](#support--contribution)
- [Licence](#licence)

---

## Présentation

Ce dossier fournit une configuration **Traefik** prête à l’emploi, portable et sécurisée, pour servir de reverse proxy à toute infrastructure Docker (WordPress, API, monitoring, etc.).

- Gestion automatique des certificats SSL (Let's Encrypt, multi-domaines, wildcard)
- Routage HTTP/HTTPS dynamique
- Dashboard sécurisé par authentification
- Sécurité renforcée (headers, redirections, isolation réseau)
- Personnalisation simple via fichier `.env`

---

## Prérequis
- Docker >= 20.x
- Docker Compose >= 1.29
- OS testé : Linux, Windows (WSL2), MacOS
- Ports 80 et 443 ouverts

---

## Installation rapide

1. **Copiez ce dossier** dans votre projet ou serveur Docker
2. **Créez un fichier `.env`** à partir de l’exemple fourni :
   ```bash
   cp .env.example .env
   ```
3. **Personnalisez les variables** dans `.env` :
   - `DOMAIN_NAME` : domaine principal (ex: monentreprise.com)
   - `TRAEFIK_EMAIL` : email pour Let's Encrypt
   - `TRAEFIK_DASHBOARD_USER` : identifiant dashboard
   - `TRAEFIK_DASHBOARD_PASSWORD_HASH` : hash du mot de passe (voir ci-dessous)
4. **Initialisez le fichier de certificats** (si besoin) :
   ```bash
   touch acme.json && chmod 600 acme.json
   ```
5. **Lancez Traefik** :
   ```bash
   docker-compose up -d
   ```

---

## Personnalisation & .env

Exemple de fichier `.env` :
```env
DOMAIN_NAME=exemple.com
TRAEFIK_EMAIL=admin@exemple.com
TRAEFIK_DASHBOARD_USER=admin
TRAEFIK_DASHBOARD_PASSWORD_HASH=$2y$05$abcdefghijklmnopqrstuv
```

---

## Générer un mot de passe hashé

### Méthode rapide (en ligne)
1. Rendez-vous sur : https://www.htaccesstools.com/htpasswd-generator/
2. Renseignez l’utilisateur et le mot de passe
3. Choisissez **Bcrypt** comme méthode
4. Copiez la partie après `admin:` dans la variable `TRAEFIK_DASHBOARD_PASSWORD_HASH` de votre `.env`

### Méthode locale (Git Bash)
```bash
htpasswd -nbB admin monmotdepasse
```

---

## Exemples d’intégration

### Extrait docker-compose.yml (standardisé)

```yaml
version: '3.8'
services:
  traefik:
    image: traefik:v3.4
    container_name: traefik
    restart: always
    security_opt:
      - no-new-privileges:true
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik.yml:/etc/traefik/traefik.yml:ro
      - ./acme.json:/etc/traefik/acme.json
    networks:
      - proxy
    env_file:
      - .env
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.traefik.rule=Host(`traefik.${DOMAIN_NAME}`)"
      - "traefik.http.routers.traefik.service=api@internal"
      - "traefik.http.routers.traefik.entrypoints=websecure"
      - "traefik.http.routers.traefik.tls=true"
      - "traefik.http.routers.traefik.tls.certresolver=letsencrypt"
      - "traefik.http.routers.traefik.middlewares=traefik-auth"
      - "traefik.http.middlewares.traefik-auth.basicauth.users=${TRAEFIK_DASHBOARD_USER}:${TRAEFIK_DASHBOARD_PASSWORD_HASH}"
networks:
  proxy:
    external: true
```

### Extrait traefik.yml (standardisé)

```yaml
api:
  dashboard: true
  insecure: false
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
  websecure:
    address: ":443"
    http:
      tls:
        certResolver: letsencrypt
        domains:
          - main: "${DOMAIN_NAME}"
            sans:
              - "*.${DOMAIN_NAME}"
providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: proxy
    watch: true
certificatesResolvers:
  letsencrypt:
    acme:
      email: "${TRAEFIK_EMAIL}"
      storage: "/etc/traefik/acme.json"
      httpChallenge:
        entryPoint: web
middlewares:
  security-headers:
    headers:
      redirectScheme:
        scheme: https
        permanent: true
      stsHeader:
        includeSubDomains: true
        preload: true
        maxAgeSeconds: 31536000
      customFrameOptionsValue: "SAMEORIGIN"
      contentTypeNosniff: true
      browserXssFilter: true
      referrerPolicy: "strict-origin-when-cross-origin"
      permissionsPolicy: "camera=(), microphone=(), geolocation=(), payment=()"
      customResponseHeaders:
        X-Robots-Tag: "none,noarchive,nosnippet,notranslate,noimageindex"
        X-Content-Type-Options: "nosniff"
  redirect-to-non-www:
    redirectRegex:
      regex: "^https://www\\.(.*)"
      replacement: "https://${1}"
      permanent: true
http:
  routers:
    main:
      rule: "Host(`${DOMAIN_NAME}`)"
      entryPoints:
        - websecure
      service: noop@internal
      middlewares:
        - security-headers
      tls:
        certResolver: letsencrypt
    www-redirect:
      rule: "Host(`www.${DOMAIN_NAME}`)"
      entryPoints:
        - websecure
      service: noop@internal
      middlewares:
        - redirect-to-non-www
      tls:
        certResolver: letsencrypt
```

### Exemple d’exposition d’un service applicatif

```yaml
services:
  monservice:
    image: monimage:latest
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.monservice.rule=Host(`api.${DOMAIN_NAME}`)"
      - "traefik.http.routers.monservice.entrypoints=websecure"
      - "traefik.http.routers.monservice.tls=true"
      - "traefik.http.routers.monservice.tls.certresolver=letsencrypt"
      - "traefik.http.services.monservice.loadbalancer.server.port=80"
```

- **Dashboard d’administration** : https://traefik.${DOMAIN_NAME} (protégé par login/mot de passe)

---

## Sécurité
- Dashboard protégé par authentification basique (bcrypt recommandé)
- Certificats SSL automatiques et renouvellement
- Headers de sécurité activés par défaut
- Redirection HTTP → HTTPS
- Possibilité de limiter l’accès au dashboard par IP (voir documentation Traefik)

---

## Maintenance
- Pour mettre à jour Traefik :
  ```bash
  docker-compose pull && docker-compose up -d
  ```
- Pour consulter les logs :
  ```bash
  docker logs traefik
  ```
- Pour vérifier les certificats :
  ```bash
  docker exec traefik traefik healthcheck
  ```
- Sauvegardez régulièrement `acme.json` pour conserver vos certificats

---

## FAQ / Dépannage

- **Erreur de certificat** :
  - Vérifiez que les ports 80 et 443 sont ouverts
  - Vérifiez les permissions de `acme.json` (`chmod 600`)
  - Vérifiez l’email et le domaine dans `.env`
  - Consultez les logs Traefik pour plus de détails
- **Dashboard inaccessible** :
  - Vérifiez les variables d’authentification dans `.env`
  - Vérifiez que le service traefik est bien démarré
- **Problème de redirection** :
  - Vérifiez les labels dans vos services
  - Vérifiez la configuration des middlewares
- **Autres questions** :
  - Consultez la [documentation officielle Traefik](https://doc.traefik.io/traefik/)

---

## Support & contribution
- Pour toute question ou contribution, ouvrez une issue ou contactez l’auteur.
- Suggestions, bugs ou demandes d’amélioration sont les bienvenus.

---

## Licence

MIT ou Commerciale – à adapter selon votre usage.

---

## Structure des fichiers

```
traefik/
├── docker-compose.yml    # Configuration Docker Compose
├── traefik.yml          # Configuration principale de Traefik
├── acme.json            # Stockage des certificats Let's Encrypt
└── .gitignore          # Fichiers à ignorer par Git
```

## Points importants (Traefik v3.4)

- **Version utilisée** : Traefik v3.4 (image officielle Docker)
- **acme.json** :
  - Chemin dans le conteneur : `/etc/traefik/acme.json`
  - Permissions : `chmod 600 acme.json` et propriétaire `root`
  - Ce fichier ne doit jamais être supprimé si vous souhaitez conserver vos certificats
- **Challenge HTTP** :
  - Ne jamais ajouter manuellement `acme-http@internal` dans les middlewares ou routers
  - Le challenge HTTP s'active uniquement via la section `certificatesResolvers` dans `traefik.yml`
  - Le port 80 doit être accessible depuis l'extérieur
- **Redémarrage** :
  - Après toute modification de configuration, redémarrer Traefik

## Extrait docker-compose.yml (exemple standardisé)

```yaml
version: '3.8'
services:
  traefik:
    image: traefik:v3.4
    container_name: traefik
    restart: always
    security_opt:
      - no-new-privileges:true
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik.yml:/etc/traefik/traefik.yml:ro
      - ./acme.json:/etc/traefik/acme.json
    networks:
      - proxy
    env_file:
      - .env
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.traefik.rule=Host(`traefik.${DOMAIN_NAME}`)"
      - "traefik.http.routers.traefik.service=api@internal"
      - "traefik.http.routers.traefik.entrypoints=websecure"
      - "traefik.http.routers.traefik.tls=true"
      - "traefik.http.routers.traefik.tls.certresolver=letsencrypt"
      - "traefik.http.routers.traefik.middlewares=traefik-auth"
      - "traefik.http.middlewares.traefik-auth.basicauth.users=${TRAEFIK_DASHBOARD_USER}:${TRAEFIK_DASHBOARD_PASSWORD_HASH}"
networks:
  proxy:
    external: true
```

## Extrait traefik.yml (exemple standardisé)

```yaml
api:
  dashboard: true
  insecure: false
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
  websecure:
    address: ":443"
    http:
      tls:
        certResolver: letsencrypt
        domains:
          - main: "${DOMAIN_NAME}"
            sans:
              - "*.${DOMAIN_NAME}"
providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: proxy
    watch: true
certificatesResolvers:
  letsencrypt:
    acme:
      email: "${TRAEFIK_EMAIL}"
      storage: "/etc/traefik/acme.json"
      httpChallenge:
        entryPoint: web
middlewares:
  security-headers:
    headers:
      redirectScheme:
        scheme: https
        permanent: true
      stsHeader:
        includeSubDomains: true
        preload: true
        maxAgeSeconds: 31536000
      customFrameOptionsValue: "SAMEORIGIN"
      contentTypeNosniff: true
      browserXssFilter: true
      referrerPolicy: "strict-origin-when-cross-origin"
      permissionsPolicy: "camera=(), microphone=(), geolocation=(), payment=()"
      customResponseHeaders:
        X-Robots-Tag: "none,noarchive,nosnippet,notranslate,noimageindex"
        X-Content-Type-Options: "nosniff"
  redirect-to-non-www:
    redirectRegex:
      regex: "^https://www\\.(.*)"
      replacement: "https://${1}"
      permanent: true
http:
  routers:
    main:
      rule: "Host(`${DOMAIN_NAME}`)"
      entryPoints:
        - websecure
      service: noop@internal
      middlewares:
        - security-headers
      tls:
        certResolver: letsencrypt
    www-redirect:
      rule: "Host(`www.${DOMAIN_NAME}`)"
      entryPoints:
        - websecure
      service: noop@internal
      middlewares:
        - redirect-to-non-www
      tls:
        certResolver: letsencrypt
```

## Conseils pour la gestion des certificats

- **Ne jamais supprimer acme.json** sans sauvegarde
- **Toujours vérifier les permissions après création ou restauration**
- **Le challenge HTTP nécessite que le port 80 soit ouvert**
- **Ne pas ajouter de routeur ou middleware acme-http@internal manuellement**
- **Les certificats sont renouvelés automatiquement**

## Dépannage

- Si les certificats ne se génèrent pas :
  - Vérifier les permissions de `acme.json` (`chmod 600` et propriétaire `root`)
  - Vérifier que le port 80 est ouvert
  - Vérifier que le challenge HTTP est bien activé dans `traefik.yml`
  - Consulter les logs pour d'éventuelles erreurs ACME

## Fonctionnalités

### 1. Gestion des certificats SSL
- Certificats Let's Encrypt automatiques
- Renouvellement automatique
- Support multi-domaines
- Challenge HTTP pour la validation

### 2. Sécurité
- Redirection HTTP vers HTTPS
- En-têtes de sécurité renforcés
- Configuration TLS optimisée
- Protection contre les attaques courantes

### 3. Middlewares
- Compression
- Redirection HTTPS
- En-têtes de sécurité
- Authentification basique

### 4. Monitoring
- Dashboard Traefik
- Logs détaillés
- Métriques de performance

## Utilisation

### 1. Ajouter un nouveau service (exemple standardisé)
Pour ajouter un nouveau service, ajoutez les labels suivants dans son `docker-compose.yml` :

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.mon-service.rule=Host(`api.${DOMAIN_NAME}`)"
  - "traefik.http.routers.mon-service.entrypoints=websecure"
  - "traefik.http.routers.mon-service.tls=true"
  - "traefik.http.routers.mon-service.tls.certresolver=letsencrypt"
  - "traefik.http.services.mon-service.loadbalancer.server.port=80"
```

### 2. Ajouter un middleware personnalisé
Dans `traefik.yml`, ajoutez dans la section `http.middlewares` :

```yaml
http:
  middlewares:
    mon-middleware:
      headers:
        customResponseHeaders:
          X-Ma-Header: "ma-valeur"
```

### 3. Redirection www vers non-www (exemple standardisé)
```yaml
labels:
  - "traefik.http.routers.www-redirect.rule=Host(`www.${DOMAIN_NAME}`)"
  - "traefik.http.routers.www-redirect.entrypoints=websecure"
  - "traefik.http.routers.www-redirect.middlewares=www-to-non-www"
  - "traefik.http.middlewares.www-to-non-www.redirectregex.regex=^https://www\\.(.*)"
  - "traefik.http.middlewares.www-to-non-www.redirectregex.replacement=https://$${1}"
  - "traefik.http.middlewares.www-to-non-www.redirectregex.permanent=true"
```

## Maintenance

### 1. Redémarrer Traefik
```bash
cd /chemin/vers/traefik
sudo docker-compose down
sudo docker-compose up -d
```

### 2. Vérifier les logs
```bash
sudo docker logs traefik
```

### 3. Vérifier les certificats
```bash
sudo docker exec traefik traefik healthcheck
```

## Bonnes pratiques

1. **Sécurité**
   - Toujours utiliser HTTPS
   - Configurer les en-têtes de sécurité
   - Limiter l'accès au dashboard
   - Utiliser des mots de passe forts

2. **Performance**
   - Activer la compression
   - Optimiser les timeouts
   - Utiliser le cache quand possible
   - Monitorer les performances

3. **Maintenance**
   - Sauvegarder régulièrement `acme.json`
   - Mettre à jour Traefik régulièrement
   - Surveiller les logs
   - Tester les redirections

## Ressources

- [Documentation officielle Traefik](https://doc.traefik.io/traefik/)
- [Let's Encrypt](https://letsencrypt.org/)
- [OWASP Security Headers](https://owasp.org/www-project-secure-headers/) 