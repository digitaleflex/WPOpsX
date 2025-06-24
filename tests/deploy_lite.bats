#!/usr/bin/env bats

# Teste l'exécution du script deploy.sh en mode Lite
@test "Le script deploy.sh s'exécute correctement en mode Lite" {
  run ./wordpress/template/deploy.sh testsite testsite.com --lite
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Déploiement terminé" ]]
}

# Valide la syntaxe du docker-compose Lite
@test "docker-compose.lite.yml est valide" {
  run docker-compose -f ./wordpress/template/docker-compose.lite.yml config
  [ "$status" -eq 0 ]
}

# Vérifie que le site WordPress est accessible après déploiement
@test "Le site WordPress est accessible après déploiement" {
  sleep 20  # Attente pour que les containers démarrent
  run curl -sL http://localhost:8080 | grep -i "wordpress"
  [ "$status" -eq 0 ]
} 