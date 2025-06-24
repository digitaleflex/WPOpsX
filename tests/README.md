# 🧪 Suite de tests WPOpsX

Ce dossier contient tous les tests automatisés du projet.

## Prérequis

- [Bats-core](https://github.com/bats-core/bats-core)
- Docker & Docker Compose
- (Optionnel) [bats-assert](https://github.com/bats-core/bats-assert)

## Lancer tous les tests

```bash
bats .
```

## Ajouter un test

1. Crée un fichier `.bats` (ex : `deploy_lite.bats`)
2. Ajoute des tests selon la syntaxe Bats
3. Les tests sont automatiquement lancés en CI

## Structure

- `deploy_lite.bats` : tests du mode Lite
- `check_services.bats` : vérification des endpoints
- `backup_restore.bats` : backup/restauration (à venir)

## Restauration automatique

- Le script [`wordpress/template/restore.sh`](../wordpress/template/restore.sh) permet de restaurer un site WordPress à partir d'une sauvegarde (fichiers + base SQL).
- Usage :
  ```bash
  ./wordpress/template/restore.sh <site_name> <backup_date>
  # Exemple : ./wordpress/template/restore.sh testsite 20240610_153000
  ```
- Un test bats vérifie la restauration automatique dans `backup_restore.bats`.

## Sécurité et robustesse de la restauration

Avant toute restauration, le script effectue automatiquement :

- Vérification des **permissions d'écriture** sur les dossiers de backup et du site
- Vérification de l'**espace disque disponible** (minimum 1 Go requis)
- Vérification de la **présence des variables d'environnement critiques** (.env, MySQL)
- Vérification que les **ports Docker nécessaires** (8080 pour WordPress, 3306 pour MySQL) ne sont pas déjà utilisés
- Vérification que le **fichier SQL n'est pas vide**
- Vérification de l'**intégrité de l'archive** de fichiers WordPress
- Vérification du **démarrage effectif de MySQL**
- Vérification de l'**accessibilité du site WordPress** après restauration

Chaque étape est loggée en temps réel, avec une barre de progression, une estimation du temps restant, et des messages d'erreur explicites en cas de problème.

## FAQ restauration

### Que faire si la restauration échoue à une étape ?
- Consultez le fichier de log `restore_<site>.log` généré dans le dossier courant. Chaque étape y est détaillée avec les erreurs éventuelles.
- Vérifiez les permissions sur les dossiers, l'espace disque, et que les ports nécessaires ne sont pas utilisés.
- Assurez-vous que la sauvegarde n'est pas corrompue ou vide.

### Comment choisir la bonne sauvegarde à restaurer ?
- Listez les sauvegardes disponibles dans `../backups/<site>/`.
- Utilisez la date du fichier (ex : `20240610_153000`) pour lancer la restauration.

### Que faire si le site ne répond pas après restauration ?
- Attendez quelques secondes, puis vérifiez avec `curl http://localhost:8080`.
- Consultez les logs Docker (`docker-compose logs wordpress_<site>`).
- Vérifiez que la base de données est bien restaurée et accessible.

## Exemple de log de restauration

```
[INFO] Arrêt des services Docker...
Progression: [====                ] 20% | Étape 2/7 | Temps écoulé: 3s | Estimé restant: 12s
[INFO] Vérification de l'intégrité de l'archive WordPress...
[INFO] Restauration des fichiers WordPress...
Progression: [========            ] 40% | Étape 4/7 | Temps écoulé: 7s | Estimé restant: 10s
[INFO] Redémarrage de la base de données...
[INFO] Restauration de la base de données...
Progression: [==============      ] 60% | Étape 6/7 | Temps écoulé: 13s | Estimé restant: 5s
[SUCCÈS] Le site WordPress est de nouveau accessible.
Progression: [====================] 100% | Étape 7/7 | Temps écoulé: 18s | Estimé restant: 0s
Restauration terminée pour testsite à partir de la sauvegarde du 20240610_153000 en 18s.
``` 