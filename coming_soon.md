# 🚧 WPOpsX – Version Lite & Roadmap à venir

## Pourquoi une version Lite ?

Pour répondre aux besoins des freelances, étudiants, micro-agences et petits VPS (1 vCPU, 1 Go RAM), nous allons proposer une **version Lite** de WPOpsX, optimisée pour les ressources limitées.



## Objectifs de la version Lite

- Déploiement WordPress/Laravel ultra-léger
- Exclusion des services lourds (Prometheus, Grafana, Jaeger, Portainer)
- Utilisation de containers Alpine et MariaDB optimisé RAM
- Backups et cron adaptés aux petits serveurs
- Simplicité d'utilisation : `./deploy.sh monsite monsite.com --lite`



## Organisation technique envisagée

- **Séparation des scripts** :
  - `deploy.sh` (détection du mode)
  - `deploy_full.sh` (stack complète)
  - `deploy_lite.sh` (stack Lite)
- **Fichiers de configuration dédiés** :
  - `docker-compose.yml` (Full)
  - `docker-compose.lite.yml` (Lite)
  - `.env.example` et `.env.lite.example`
- **Documentation claire** :
  - README principal
  - Section ou fichier dédié à la version Lite
  - Tableau comparatif des modes



## Roadmap (prochaines étapes)

- [ ] Rédiger la documentation détaillée du mode Lite
- [ ] Créer les scripts et fichiers de config séparés
- [ ] Automatiser les tests CI pour chaque mode
- [ ] Ajouter un tableau comparatif dans le README
- [ ] Préparer une interface web de déploiement (long terme)



## Principes à respecter

- **Modularité** : chaque composant doit pouvoir être activé/désactivé facilement
- **Lisibilité** : code et doc séparés pour chaque mode
- **Évolutivité** : architecture prête pour d'autres modules (backups S3, alerting, etc.)
- **Simplicité d'usage** : une commande, un résultat fiable



## 📊 Tableau comparatif : WPOpsX – Full vs Lite

| Fonctionnalité                        | Version Full ✅ | Version Lite 🟢 | Détail                                 |
||:--:|:--:|-|
| Déploiement WP/Laravel automatisé     |       ✅        |       ✅        | deploy.sh dans les deux                |
| Reverse Proxy Traefik + SSL           |       ✅        |       ✅        | Auto-renouvellement intégré            |
| Base de données MariaDB optimisée     |       ✅        |   ✅ (allégée)  | Buffers réduits en Lite                |
| Monitoring Prometheus + Grafana       |       ✅        |       ❌        | Option à activer à la main             |
| Traceur Jaeger                        |       ✅        |       ❌        | Pour environments DevOps +             |
| Portainer (UI Docker)                 |       ✅        |   ❌ (option)   | Désactivé par défaut                   |
| Sauvegardes automatiques              |       ✅        |       ✅        | Rotation ajustée pour Lite             |
| Restauration manuelle rapide          |       ✅        |       ✅        | Scripts communs                        |
| En-têtes de sécurité HTTP             |       ✅        |       ✅        | Proxy + webserver sécurisé             |
| Cron système (WP-Cron désactivé)      |       ✅        |       ✅        | Performance améliorée                  |
| Mode multi-sites                      |       ✅        |   🔸 limité     | Possible avec tuning VPS               |
| Déploiement en 1 commande             |       ✅        |   ✅ (--lite)   | Interface CLI unifiée                  |
| Templates extensibles                 |       ✅        |       ✅        | Même base technique                    |
| CI/CD / GitHub Actions                |       🔜        |       🔜        | Prévu pour les deux                    |
| Utilisation minimale recommandée      | VPS 2 vCPU/4Go | VPS 1 vCPU/1Go | VPS low-cost friendly                  |



## 💡 Idées et pistes d'amélioration

- **Feedback & Beta Testeurs** : ouvrir un canal Discord/Slack ou un formulaire pour recueillir les retours sur la version Lite.
- **Quickstart ultra-court** : proposer un encart "Essayer la version Lite en 2 minutes" avec un copier-coller unique.
- **Badge "Lite Ready" ou "Lite Beta"** : afficher un badge dans le README dès que la version Lite est testable.
- **Script de benchmark** : permettre aux utilisateurs de comparer la consommation RAM/CPU entre Full et Lite.
- **Mode debug** : ajouter une option `--debug` pour générer des logs détaillés et faciliter le support.
- **FAQ dédiée Lite** : répondre aux limitations, astuces et bonnes pratiques spécifiques à la version Lite.
- **Cas d'usage concrets** : documenter des scénarios réels (blog étudiant, micro-agence, etc.).
- **Release party / webinaire** : organiser une démo live pour présenter la version Lite et recueillir des feedbacks.
- **Lite Starter Pack** : fournir un template `.env.lite.example`, un script d'optimisation MariaDB, un guide sécurité VPS low-cost.
- **Monétisation / support pro** : envisager un support payant, une version Pro ou des modules additionnels.



## 📚 Centralisation de la documentation

Un dossier `docs/` sera créé pour centraliser toute la documentation détaillée (guides, FAQ, cas d'usage, benchmarks, etc.) en attendant la mise en ligne du site officiel.

N'hésitez pas à contribuer à ce dossier ou à proposer des idées de documentation !



> Ce fichier sert de feuille de route et de mémo pour l'équipe/contributeurs. N'hésitez pas à proposer vos idées ou à ouvrir une issue ! 