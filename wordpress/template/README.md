# Script de Déploiement WordPress

[![Docker](https://img.shields.io/badge/docker-ready-blue?logo=docker)](https://www.docker.com/)
[![Licence MIT](https://img.shields.io/badge/licence-MIT-green)](./LICENSE)
[![Contributions welcome](https://img.shields.io/badge/contributions-welcome-brightgreen)](../../)

## Sommaire
- [Introduction](#introduction)
- [Fonctionnalités](#fonctionnalités)
- [Prérequis](#prérequis)
- [Utilisation](#utilisation)
- [Validation des Domaines](#validation-des-domaines)
- [Structure du Déploiement](#structure-du-déploiement)
- [Sécurité](#sécurité)
- [Maintenance](#maintenance)
- [Dépannage](#dépannage)
- [Notes Importantes](#notes-importantes)
- [Contribution](#contribution)
- [FAQ / Dépannage](#faq--dépannage)
- [Licence](#licence)

Ce script permet de déployer automatiquement une instance WordPress avec Docker Compose, en utilisant une approche entièrement conteneurisée.

## Fonctionnalités

- Déploiement entièrement conteneurisé avec Docker
- Gestion automatique des permissions via Docker
- Configuration automatique de :
  - WordPress avec PHP optimisé
  - MariaDB avec paramètres optimisés
  - Redis pour le cache
  - Traefik pour le reverse proxy et SSL
  - Sauvegardes automatiques
  - Surveillance avec Prometheus et Grafana
  - Mises à jour automatiques

## Prérequis

- Docker
- Docker Compose
- Accès root ou sudo
- Domaine configuré avec DNS (domaine principal ou sous-domaine)

## Utilisation

```bash
./deploy.sh [options] <site_name> <domain_name>
```

### Options

- `-t, --type TYPE` : Type d'application (wordpress, laravel, etc.)
- `-m, --mysql VER` : Version de MySQL/MariaDB
- `-r, --redis VER` : Version de Redis
- `-w, --wp VER` : Version de WordPress
- `-i, --wp-image IMG` : Image WordPress à utiliser
- `-h, --help` : Affiche l'aide

### Exemples

```bash
# Déploiement WordPress sur un domaine principal
./deploy.sh -t wordpress blog blog.digitaleflex.com

# Déploiement WordPress sur un sous-domaine
./deploy.sh -t wordpress insight insight.digitaleflex.com

# Déploiement avec versions spécifiques
./deploy.sh -t wordpress --mysql 10.11 --redis 7-alpine blog blog.digitaleflex.com

# Déploiement avec image personnalisée
./deploy.sh -t wordpress --wp-image eflexcloud/wordpress-custom blog blog.digitaleflex.com
```

### Validation des Domaines

Le script accepte :
- Domaines principaux (ex: example.com)
- Sous-domaines (ex: sub.example.com)
- Sous-domaines multiples (ex: sub1.sub2.example.com)

Format valide :
- Caractères alphanumériques
- Tirets (-)
- Points (.) pour séparer les parties du domaine
- Extension de domaine d'au moins 2 caractères

## Structure du Déploiement

Le script crée une structure Docker Compose avec :

### Services

1. **WordPress**
   - Image personnalisée avec PHP optimisé
   - Configuration automatique via variables d'environnement
   - Gestion des permissions via Docker
   - Volume Docker pour la persistance des données

2. **MariaDB**
   - Configuration optimisée pour WordPress
   - Volume Docker pour la persistance des données
   - Healthcheck intégré

3. **Redis**
   - Cache pour WordPress
   - Configuration sécurisée
   - Volume Docker pour la persistance

4. **Traefik**
   - Reverse proxy automatique
   - Gestion SSL avec Let's Encrypt
   - Redirection www vers non-www
   - Support des sous-domaines

### Volumes

- `wordpress_data_<site_name>` : Données WordPress
- `db_data_<site_name>` : Base de données MariaDB
- `redis_data_<site_name>` : Données Redis

### Réseaux

- `proxy` : Réseau externe pour Traefik
- `<site_name>_network` : Réseau interne pour les services
- `redis_network` : Réseau pour Redis

## Sécurité

- Permissions gérées par Docker
- Configuration sécurisée de MariaDB
- Redis protégé par mot de passe
- Traefik avec SSL automatique
- Pas d'accès direct aux fichiers sur l'hôte

## Maintenance

### Sauvegardes

Les sauvegardes sont automatiquement configurées :
- Base de données quotidienne
- Fichiers WordPress quotidiens
- Rotation des sauvegardes (7 jours)

### Mises à jour

Les mises à jour sont automatiquement configurées :
- WordPress core
- Plugins
- Thèmes
- Traductions

### Surveillance

- Prometheus pour la collecte de métriques
- Grafana pour la visualisation
- Alertes configurables

## Dépannage

### Logs

```bash
# Logs WordPress
docker-compose logs wordpress_<site_name>

# Logs MariaDB
docker-compose logs mysql_<site_name>

# Logs Redis
docker-compose logs redis_<site_name>
```

### Commandes Utiles

```bash
# Redémarrer les services
docker-compose restart

# Vérifier l'état des services
docker-compose ps

# Voir les volumes
docker volume ls

# Nettoyer les volumes non utilisés
docker volume prune
```

## Notes Importantes

- Toutes les données sont stockées dans des volumes Docker
- Les permissions sont gérées par Docker
- Pas besoin de configuration manuelle des permissions
- Les sauvegardes sont automatiques
- Les mises à jour sont automatiques
- Support complet des sous-domaines

## Contribution

Les contributions sont les bienvenues ! N'hésitez pas à :
1. Fork le projet
2. Créer une branche pour votre fonctionnalité
3. Commiter vos changements
4. Pousser vers la branche
5. Ouvrir une Pull Request 

## FAQ / Dépannage

### Le script s'arrête avec une erreur "Docker n'est pas installé"
- Vérifiez que Docker et Docker Compose sont bien installés et accessibles dans votre terminal.

### Le domaine est refusé comme invalide
- Vérifiez le format du domaine (pas d'espaces, caractères spéciaux interdits, extension correcte).
- Exemple valide : `blog.monsite.com`

### Les services ne démarrent pas ou restent en "restarting"
- Vérifiez l'espace disque disponible.
- Consultez les logs avec `docker-compose logs` pour plus de détails.

### Les certificats SSL ne sont pas générés
- Vérifiez que le port 80 est ouvert et accessible depuis l'extérieur.
- Vérifiez les logs Traefik pour d'éventuelles erreurs ACME.

### Impossible d'accéder au site après déploiement
- Attendez quelques minutes (génération des certificats, démarrage des services).
- Vérifiez que le DNS pointe bien vers votre serveur.

### Les sauvegardes automatiques ne fonctionnent pas
- Vérifiez les permissions sur le dossier de sauvegarde.
- Consultez la crontab (`crontab -l`) pour vérifier la présence de la tâche.

---

## Licence

MIT – Utilisation libre, voir le fichier LICENSE pour plus de détails.

--- 