#!/usr/bin/env bats

# Teste la création d'une sauvegarde après déploiement
@test "Une sauvegarde est créée après le déploiement" {
  run ./wordpress/template/deploy.sh testsite testsite.com --lite
  [ "$status" -eq 0 ]
  backup_dir="../backups/testsite"
  run ls -1 $backup_dir | grep -E 'db_.*\\.sql|files_.*\\.tar.gz'
  [ "$status" -eq 0 ]
}

# (Optionnel) Teste la restauration à partir d'une sauvegarde
@test "La restauration fonctionne à partir d'une sauvegarde" {
  # Supposons qu'une sauvegarde existe déjà pour testsite à la date 20240610_153000
  backup_date="$(ls -1 ../backups/testsite/db_*.sql | head -n1 | sed 's/.*db_\(.*\)\.sql/\1/')"
  [ -n "$backup_date" ]
  run ./wordpress/template/restore.sh testsite "$backup_date"
  [ "$status" -eq 0 ]
  # Vérifie que le site WordPress est de nouveau accessible
  sleep 20
  run curl -sL http://localhost:8080 | grep -i "wordpress"
  [ "$status" -eq 0 ]
} 