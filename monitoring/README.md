# Monitoring — Prometheus, Grafana, Jaeger

Supervision de l'hôte et des conteneurs : métriques système, métriques des conteneurs, métriques du
reverse proxy et traces applicatives.

## Sommaire

- [Démarrage](#démarrage)
- [Services](#services)
- [Accès aux interfaces](#accès-aux-interfaces)
- [Configuration](#configuration)
- [Superviser la base d'un site](#superviser-la-base-dun-site)
- [Maintenance](#maintenance)
- [Dépannage](#dépannage)

## Démarrage

```bash
../scripts/init.sh                       # réseau proxy, .env des modules
cp .env.example .env && chmod 600 .env   # puis renseigner les identifiants
docker compose up -d
docker compose ps
```

> `docker compose up` **échoue volontairement** si `MONITORING_AUTH_*` ou `GRAFANA_ADMIN_PASSWORD` sont
> absents : une stack de supervision exposée sans authentification est une fuite de données
> d'infrastructure (noms d'hôtes, images, volumes, consommation).

## Services

| Service | Rôle | Port interne | Accès |
|---|---|---|---|
| `prometheus` | collecte des métriques | 9090 | `https://prometheus.<DOMAIN_NAME>` (auth) |
| `grafana` | tableaux de bord | 3000 | `https://grafana.<DOMAIN_NAME>` (auth) |
| `jaeger` | traces distribuées | 16686 | `https://jaeger.<DOMAIN_NAME>` (auth) |
| `node-exporter` | métriques de l'hôte | 9100 | interne |
| `cadvisor` | métriques des conteneurs | 8080 | interne |

Aucun port n'est publié sur l'hôte : tout passe par Traefik (TLS + authentification basique). Pour un
accès local de secours, publier explicitement sur la boucle locale, par exemple
`"127.0.0.1:9090:9090"`.

### Authentification

Le middleware `monitoring-auth` est déclaré sur le service `prometheus` (provider Docker) et réutilisé par
les routers Grafana et Jaeger. Le hash doit être fourni en bcrypt avec les `$` **doublés** dans le `.env`
(Compose consomme un `$` isolé et tronquerait le hash) :

```bash
htpasswd -nbB admin 'monmotdepasse'
# -> admin:$2y$05$xxxx   ==>  MONITORING_AUTH_PASSWORD_HASH=$$2y$$05$$xxxx
```

## Accès aux interfaces

- **Prometheus** : `https://prometheus.<DOMAIN_NAME>`
- **Grafana** : `https://grafana.<DOMAIN_NAME>` — identifiants `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD`
- **Jaeger** : `https://jaeger.<DOMAIN_NAME>`

## Configuration

### Cibles Prometheus

`prometheus/prometheus.yml` collecte :

| Job | Cible | Note |
|---|---|---|
| `prometheus` | `localhost:9090` | auto-surveillance |
| `node-exporter` | `node-exporter:9100` | CPU, RAM, disque, réseau de l'hôte |
| `cadvisor` | `cadvisor:8080` | conteneurs Docker |
| `traefik` | `traefik:8082` | entryPoint `metrics` du reverse proxy |

Les cibles `wordpress`, `mysql` et `redis` ont été retirées : aucun exporter ne les exposait, ce qui
produisait trois cibles **DOWN** permanentes et de fausses alertes.

### Tableaux de bord

Provisionner un dossier de dashboards JSON dans `grafana/provisioning/dashboards/` pour les rendre
permanents :

```yaml
# grafana/provisioning/dashboards/dashboards.yml
apiVersion: 1
providers:
  - name: WPOpsX
    folder: WPOpsX
    type: file
    options:
      path: /etc/grafana/provisioning/dashboards
```

Dashboards recommandés : Node Exporter Full (1860), Docker/cAdvisor (14282), Traefik (17346) — identifiants
du catalogue Grafana.

## Superviser la base d'un site

Les bases des sites sont sur leur réseau interne (donc invisibles depuis Prometheus : c'est voulu).
Pour en superviser une, ajouter l'exporter **à côté du site** et le raccorder au réseau `proxy`, que
Prometheus partage déjà :

```yaml
# wordpress/<site>/docker-compose.yml
  mysqld-exporter:
    image: prom/mysqld-exporter:v0.15.1
    container_name: mysqld-exporter-<site>
    environment:
      MYSQLD_EXPORTER_PASSWORD: ${MYSQL_PASSWORD}
    command:
      - '--mysqld.address=mysql:3306'
      - '--mysqld.username=${MYSQL_USER}'
    networks: [internal, proxy]
    labels: ["traefik.enable=false"]
```

puis ajouter la cible `mysqld-exporter-<site>:9104` dans `prometheus/prometheus.yml` et recharger
Prometheus. Même principe pour Redis avec `oliver006/redis_exporter` (port 9121).

## Maintenance

```bash
# Sauvegarde
docker run --rm -v monitoring_prometheus_data:/source -v "$PWD/backup:/backup" \
    prom/prometheus:v3.4.1 tar czf /backup/prometheus.tar.gz -C /source .
docker run --rm -v monitoring_grafana_data:/source -v "$PWD/backup:/backup" \
    grafana/grafana:11.6.1 tar czf /backup/grafana.tar.gz -C /source .

# Restauration
docker compose down
docker run --rm -v monitoring_prometheus_data:/target -v "$PWD/backup:/backup" \
    prom/prometheus:v3.4.1 sh -c "rm -rf /target/* && tar xzf /backup/prometheus.tar.gz -C /target"
docker compose up -d
```

Toutes les images sont épinglées et suivies par Dependabot (`.github/dependabot.yml`).

## Dépannage

| Symptôme | Piste |
|---|---|
| Les interfaces ne répondent pas | le service doit être sur le réseau `proxy` (déjà configuré) ; `docker logs traefik \| grep -i "no available server"` |
| `GRAFANA_ADMIN_PASSWORD manquant` | le `.env` n'est pas rempli : `cp .env.example .env` |
| Authentification refusée partout | hash mal formé : vérifier les `$$` dans le `.env` |
| Les métriques de conteneurs sont vides | cAdvisor a besoin de `cap_add: [SYS_ADMIN, SYS_PTRACE]` et de `/dev/kmsg` (déjà configuré) ; le mode `privileged: true` donne des métriques exhaustives |
| Une cible est DOWN | `https://prometheus.<DOMAIN_NAME>/targets` indique la cause exacte |

## Licence

MIT — voir [LICENSE](../LICENSE).
