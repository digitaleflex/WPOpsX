# Guide d'Utilisation du Monitoring

## Table des matières
1. [Introduction](#introduction)
2. [Installation](#installation)
3. [Accès aux interfaces](#accès-aux-interfaces)
4. [Configuration](#configuration)
5. [Tableaux de bord](#tableaux-de-bord)

## Introduction

Cette configuration de monitoring comprend :
- Prometheus : Collecte et stockage des métriques
- Grafana : Visualisation des métriques
- Jaeger : Traçage distribué
- Node Exporter : Métriques système
- cAdvisor : Métriques des conteneurs

## Installation

1. Créez les dossiers nécessaires :
```bash
mkdir -p monitoring/prometheus monitoring/grafana/provisioning/datasources
```

2. Copiez les fichiers de configuration :
```bash
cp docker-compose.yml monitoring/
cp prometheus.yml monitoring/prometheus/
cp prometheus.yml monitoring/grafana/provisioning/datasources/
```

3. Démarrez les services :
```bash
cd monitoring
docker-compose up -d
```

## Variables d'environnement

Avant de démarrer la stack, copiez le fichier `.env.example` en `.env` et personnalisez les variables selon vos besoins :

- `GRAFANA_ADMIN_USER` : identifiant administrateur Grafana (par défaut : admin)
- `GRAFANA_ADMIN_PASSWORD` : mot de passe administrateur Grafana (par défaut : admin)
- `DOMAIN_NAME` : domaine principal utilisé pour accéder aux dashboards (Prometheus, Grafana, Jaeger...)

```bash
cp .env.example .env
# puis éditez .env
```

## Accès aux interfaces

### Prometheus
- URL : `https://prometheus.votre-domaine.com`
- Port : 9090
- Pas d'authentification par défaut

### Grafana
- URL : `https://grafana.votre-domaine.com`
- Port : 3000
- Identifiants par défaut :
  - Utilisateur : admin
  - Mot de passe : admin

### Jaeger
- URL : `https://jaeger.votre-domaine.com`
- Port : 16686
- Pas d'authentification par défaut

## Configuration

### Prometheus
Le fichier `prometheus.yml` configure les cibles de collecte :
- Prometheus lui-même
- Node Exporter
- cAdvisor
- WordPress
- MySQL
- Redis

### Grafana
Les sources de données sont configurées dans :
- `grafana/provisioning/datasources/prometheus.yml`

## Tableaux de bord recommandés

### Pour Grafana
1. **Système**
   - ID : 1860 (Node Exporter Full)
   - URL : https://grafana.com/grafana/dashboards/1860

2. **Docker**
   - ID : 893 (Docker & System Monitoring)
   - URL : https://grafana.com/grafana/dashboards/893

3. **WordPress**
   - ID : 11159 (WordPress Monitoring)
   - URL : https://grafana.com/grafana/dashboards/11159

### Pour Jaeger
- Utilisez l'interface web pour visualiser les traces
- Filtrez par service pour voir les performances

## Maintenance

### Sauvegarde
```bash
# Sauvegarder les données Prometheus
docker run --rm -v prometheus_data:/source -v $(pwd)/backup:/backup alpine tar czf /backup/prometheus.tar.gz -C /source .

# Sauvegarder les données Grafana
docker run --rm -v grafana_data:/source -v $(pwd)/backup:/backup alpine tar czf /backup/grafana.tar.gz -C /source .
```

### Restauration
```bash
# Restaurer Prometheus
docker run --rm -v prometheus_data:/target -v $(pwd)/backup:/backup alpine sh -c "rm -rf /target/* && tar xzf /backup/prometheus.tar.gz -C /target"

# Restaurer Grafana
docker run --rm -v grafana_data:/target -v $(pwd)/backup:/backup alpine sh -c "rm -rf /target/* && tar xzf /backup/grafana.tar.gz -C /target"
```

## Dépannage

### Problèmes courants

1. **Prometheus ne collecte pas les métriques**
   - Vérifiez les logs : `docker-compose logs prometheus`
   - Vérifiez la connectivité réseau
   - Vérifiez les cibles dans l'interface web

2. **Grafana ne peut pas se connecter à Prometheus**
   - Vérifiez l'URL dans la configuration
   - Vérifiez la connectivité réseau
   - Vérifiez les logs : `docker-compose logs grafana`

3. **Jaeger ne montre pas de traces**
   - Vérifiez que l'instrumentation est correcte
   - Vérifiez les logs : `docker-compose logs jaeger`

## Sécurité

1. **Changez les mots de passe par défaut**
2. **Limitez l'accès aux interfaces**
3. **Utilisez HTTPS**
4. **Configurez l'authentification si nécessaire**

## Mise à jour

Pour mettre à jour les services :
```bash
docker-compose pull
docker-compose up -d
``` 