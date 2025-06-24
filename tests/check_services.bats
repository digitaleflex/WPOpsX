#!/usr/bin/env bats

# Vérifie que le dashboard Traefik est accessible
@test "Dashboard Traefik accessible" {
  run curl -sL http://localhost:8081 | grep -i "traefik"
  [ "$status" -eq 0 ]
}

# Vérifie que le dashboard Portainer est accessible (si activé)
@test "Dashboard Portainer accessible" {
  run curl -sL http://localhost:9000 | grep -i "portainer"
  [ "$status" -eq 0 ]
} 