#!/bin/bash

# Script para generar un docker-compose.yml básico a partir de contenedores en ejecución.
# REQUIERE tener instalado 'jq' (sudo apt install jq o similar).

COMPOSE_VERSION="3.8"  # Versión de docker-compose que usarás (puedes ajustarla)

echo "version: '${COMPOSE_VERSION}'"
echo "services:"

docker ps --format "{{.ID}}" | while read container_id; do
  container_name=$(docker inspect --format '{{.Name}}' "$container_id" | sed 's/^\///') # Obtener nombre y quitar la '/' inicial
  image_name=$(docker inspect --format '{{.Config.Image}}' "$container_id")

  echo "  ${container_name}:"
  echo "    image: ${image_name}"

  # Puertos (CORRECTED jq COMMAND)
  ports_config=$(docker inspect --format '{{json .HostConfig.PortBindings}}' "$container_id" | jq -r 'to_entries[] | .key as $container_port | .value[] | "\(.HostPort):" + ($container_port | split("/")[0])')
  if [[ -n "$ports_config" ]]; then
    echo "    ports:"
    while IFS= read -r port_mapping; do
      echo "      - \"${port_mapping}\""
    done <<< "$ports_config"
  fi

  # Volúmenes (solo bind mounts básicos, los volúmenes nombrados pueden ser más complejos)
  volumes_config=$(docker inspect --format '{{json .Mounts}}' "$container_id" | jq -r '.[] | select(.Type == "bind") | "\(.Source):\(.Destination)\""')
  if [[ -n "$volumes_config" ]]; then
    echo "    volumes:"
    while IFS= read -r volume_mapping; do
      echo "      - \"${volume_mapping}\""
    done <<< "$volumes_config"
  fi

  # Variables de entorno (solo las definidas en el contenedor, NO PUEDE DISTINGUIR las originales de la imagen BASE)
  env_config=$(docker inspect --format '{{json .Config.Env}}' "$container_id" | jq -r '.[] | split("=") | { (.[0]): .[1] } | to_entries[] | .key + ": \"" + .value + "\""')
  if [[ -n "$env_config" ]]; then
    echo "    environment:"
    echo "      # WARNING: The following environment variables might include defaults from the base image."
    echo "      # Please review and remove any variables that were NOT explicitly set in your original docker-compose.yml."
    while IFS= read -r env_line; do
      echo "      ${env_line}"
    done <<< "$env_config"
  fi

  # Restart policy (si está configurada, 'unless-stopped' es común)
  restart_policy=$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' "$container_id")
  if [[ "$restart_policy" == "unless-stopped" ]]; then
    echo "    restart: unless-stopped"
  fi

  echo "" # Línea en blanco entre servicios
done

echo "# Fin del docker-compose.yml generado. REVISA Y EDITA MANUALMENTE."
echo "# WARNING: The generated environment variables might include defaults from the base image."
echo "# Please review and remove any variables that were NOT explicitly set in your original docker-compose.yml."