#!/bin/bash

idmp_url="http://localhost:6042"
license_server_addr="http://localhost:6059"
compose_file="docker-compose.yml"
compose_cmd=""
compose_supports_pull_policy=0
need_check_memory=0
mode_from_cli=0
MIN_DOCKER_MEMORY=10737418240  # 10GB in bytes

GREEN_DARK='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

function log() {
  case "$1" in
    info)
      echo -e "${GREEN_DARK}[INFO]${NC} $2"
      ;;
    warn)
      echo -e "${YELLOW}[WARN]${NC} $2"
      ;;
    error)
      echo -e "${RED}[ERROR]${NC} $2"
      ;;
  esac
}

function show_help() {
  echo "Usage: $0 [COMMAND] [OPTIONS]"

  echo -e "\nCommands:"
  echo -e "  start\t\t\tStart the IDMP services"
  echo -e "  stop\t\t\tStop the IDMP services"
  echo -e "  clean\t\t\tClean the current IDMP environment"

  echo -e "\nOptions:"
  echo -e "  --mode MODE\t\tDeployment mode: 1|standard or 2|full (skip interactive prompt)"
  echo -e "  -h, --help\t\tShow this help message"

  echo -e "\nExamples:"
  echo -e "  $0 start\t\t\t# Start with interactive mode"
  echo -e "  $0 start --mode full\t\t# Start Full deployment (TSDB + IDMP + TDgpt + CLS + TDModel)"
  echo -e "  $0 start --mode 2\t\t# Same as --mode full"
  echo -e "  $0 start --mode standard\t# Start Standard deployment (TSDB + IDMP)"
  echo -e "  $0 stop\t\t\t# Stop services"
  echo -e "  $0 clean --mode full\t\t# Clean Full deployment environment"
}

function apply_deploy_mode() {
  case "$1" in
    1|standard)
      compose_file="docker-compose.yml"
      need_check_memory=0
      log info "Selected: Standard deployment (TSDB Enterprise + IDMP + CLS)"
      ;;
    2|full)
      compose_file="docker-compose-tdgpt.yml"
      need_check_memory=1
      log info "Selected: Full deployment (TSDB Enterprise + IDMP + TDgpt + CLS + TDModel)"
      ;;
    *)
      log error "Invalid mode: $1 (use 1|standard or 2|full)"
      exit 1
      ;;
  esac
}

function parse_arguments() {
  if [[ $# -eq 0 ]]; then
    log error "No command provided.\n"
    show_help
    exit 1
  fi

  while [[ $# -gt 0 ]]; do
    case $1 in
      start|stop|clean)
        action="$1"
        shift
        ;;
      --mode)
        if [[ -z "${2:-}" ]]; then
          log error "--mode requires a value: 1|standard or 2|full"
          exit 1
        fi
        apply_deploy_mode "$2"
        mode_from_cli=1
        shift 2
        ;;
      --mode=*)
        apply_deploy_mode "${1#*=}"
        mode_from_cli=1
        shift
        ;;
      -h|--help)
        show_help
        exit 0
        ;;
      *)
        log error "Unknown option: $1"
        show_help
        exit 1
        ;;
    esac
  done
}

function check_docker_compose() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    compose_cmd="docker compose"
    compose_supports_pull_policy=1
    log info "Found docker compose plugin"
  elif command -v docker-compose >/dev/null 2>&1 && docker-compose version >/dev/null 2>&1; then
    compose_cmd="docker-compose"
    compose_supports_pull_policy=0
    log info "Found docker-compose command"
  else
    log error "Neither 'docker-compose' nor 'docker compose' command found!"
    log error "Please install Docker Compose first"
    exit 1
  fi
}

function check_docker_memory() {
  local mem_limit
  mem_limit=$(docker info --format '{{.MemTotal}}')
  if [[ -z "$mem_limit" || "$mem_limit" -eq 0 ]]; then
    log warn "Unable to detect Docker memory limit, please ensure Docker is running."
    exit 1
  fi
  local mem_gb=$((mem_limit / 1024 / 1024 / 1024))
  if (( mem_limit < MIN_DOCKER_MEMORY )); then
    log warn "Docker memory limit is less than 10GB (current: ${mem_gb}GB)."
    log warn "Please increase Docker's memory limit to at least 10GB and try again."
    exit 1
  else
    log info "Docker memory limit check passed: ${mem_gb}GB"
  fi
}

function select_compose_mode() {
  if [[ ${mode_from_cli} -eq 1 ]]; then
    return
  fi

  echo -e "${GREEN_DARK}Please select deployment mode:${NC}"
  echo "1) Standard deployment (TSDB Enterprise + IDMP + CLS) (docker-compose.yml)"
  echo "2) Full deployment (TSDB Enterprise + IDMP + TDgpt + CLS + TDModel) (docker-compose-tdgpt.yml)"

  while true; do
    printf "%b" "${GREEN_DARK}Enter your choice [1-2]: ${NC}"
    read -r mode_choice

    case "$mode_choice" in
      1|"")
        apply_deploy_mode "1"
        break
        ;;
      2)
        apply_deploy_mode "2"
        break
        ;;
      *)
        echo -e "${YELLOW}Invalid choice. Please enter 1 or 2.${NC}"
        ;;
    esac
  done
}

function setup_url() {
  local host_ip

  if command -v ip >/dev/null 2>&1; then
    host_ip=$(ip addr | grep 'inet ' | grep -vE '127.0.0.1|docker' | awk '{print $2}' | cut -d/ -f1 | head -n1)
  elif command -v ifconfig >/dev/null 2>&1; then
    host_ip=$(ifconfig | awk '/^[a-zA-Z0-9]/ {iface=$1} /inet / && iface !~ /^(docker|br-|veth)/ && $2!="127.0.0.1" {print $2}'| head -n1)
  else
    log warn "Neither 'ip' nor 'ifconfig' command found. Using default URL."
  fi

  if [[ "$host_ip" =~ ^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$ ]]; then
    idmp_url="http://${host_ip}:6042"
  else
    log warn "Failed to detect a valid IP address: ${host_ip}"
  fi

  while true; do
    printf "%b" "${GREEN_DARK}Do you want to use this URL to access IDMP web console? ${idmp_url} [Y/n] ${NC}"
    read -r use_default_url
    if [[ -z "$use_default_url" || "$use_default_url" =~ ^[Yy]$ ]]; then
      break
    elif [[ "$use_default_url" =~ ^[Nn]$ ]]; then
      printf "%b" "${GREEN_DARK}Please input IDMP URL (http://<ip>:6042): ${NC}"
      read -r new_idmp_url
      idmp_url="${new_idmp_url:-$idmp_url}"
      break
    else
      echo -e "${YELLOW}Please enter y, n, or press Enter (default Y).${NC}"
    fi
  done

  log info "IDMP Server URL: ${idmp_url}"
}

function setup_license_server_addr() {
  # Default to the same host as IDMP URL, port 6059
  if [[ "$idmp_url" =~ ^(https?://[^:/]+)(:[0-9]+)?(/.*)?$ ]]; then
    license_server_addr="${BASH_REMATCH[1]}:6059"
  else
    license_server_addr="http://localhost:6059"
  fi

  while true; do
    printf "%b" "${GREEN_DARK}Do you want to use this URL for license server ? ${license_server_addr} [Y/n] ${NC}"
    read -r use_default_license
    if [[ -z "$use_default_license" || "$use_default_license" =~ ^[Yy]$ ]]; then
      break
    elif [[ "$use_default_license" =~ ^[Nn]$ ]]; then
      printf "%b" "${GREEN_DARK}Please input license server URL (http://<ip>:6059): ${NC}"
      read -r new_license_server_addr
      license_server_addr="${new_license_server_addr:-$license_server_addr}"
      break
    else
      echo -e "${YELLOW}Please enter y, n, or press Enter (default Y).${NC}"
    fi
  done

  log info "License Server URL: ${license_server_addr}"
}

function check_and_upgrade_images() {
  local images=()

  images+=("tdengine/tsdb-ee:${TSDB_TAG:-latest}")
  images+=("tdengine/idmp-backend-ee:${IDMP_TAG:-latest}")
  images+=("tdengine/idmp-ui-ee:${IDMP_TAG:-latest}")
  images+=("tdengine/idmp-ai-ee:${IDMP_AI_TAG:-latest}")
  images+=("tdengine/cls:${CLS_TAG:-latest}")
  if [[ "$compose_file" == "docker-compose-tdgpt.yml" ]]; then
    images+=("tdengine/tdgpt-full:${TDGPT_TAG:-latest}")
    images+=("tdengine/tdmodel:${TDMODEL_TAG:-latest}")
  fi

  log info "Checking local images..."

  local missing_images=()
  local existing_images=()
  local image_ref
  for image_ref in "${images[@]}"; do
    if ! docker image inspect "$image_ref" >/dev/null 2>&1; then
      missing_images+=("$image_ref")
      continue
    fi

    existing_images+=("$image_ref")
  done

  if [[ ${#missing_images[@]} -gt 0 ]]; then
    echo -e "${YELLOW}The following images do not exist locally and will be pulled by Docker Compose on start:${NC}"
    for image_ref in "${missing_images[@]}"; do
      echo "  - $image_ref"
    done
  fi

  [[ ${#existing_images[@]} -eq 0 ]] && return 0

  echo -e "${YELLOW}The following images already exist locally:${NC}"
  for image_ref in "${existing_images[@]}"; do
    echo "  - $image_ref"
  done

  while true; do
    printf "%b" "${GREEN_DARK}Do you want to update existing images? [Y/n] ${NC}"
    read -r upgrade_choice
    if [[ -z "$upgrade_choice" || "$upgrade_choice" =~ ^[Yy]$ ]]; then
      log info "Pulling latest images with Docker Compose..."
      if [[ ${compose_supports_pull_policy} -eq 1 ]]; then
        ${compose_cmd} -f "${compose_file}" pull --policy always
      else
        ${compose_cmd} -f "${compose_file}" pull
      fi
      break
    elif [[ "$upgrade_choice" =~ ^[Nn]$ ]]; then
      log info "Skipping update, using existing images."
      break
    else
      echo -e "${YELLOW}Please enter y, n, or press Enter (default Y).${NC}"
    fi
  done
}

function ask_git_enable() {
  while true; do
    printf "%b" "${GREEN_DARK}Do you want to disable git version control (experimental)? [Y/n] ${NC}"
    read -r git_choice
    if [[ -z "$git_choice" || "$git_choice" =~ ^[Yy]$ ]]; then
      export TDA_GIT_ENABLE=false
      log info "Git version control disabled."
      break
    elif [[ "$git_choice" =~ ^[Nn]$ ]]; then
      export TDA_GIT_ENABLE=true
      log info "Git version control enabled."
      break
    else
      echo -e "${YELLOW}Please enter y, n, or press Enter (default Y, y disables).${NC}"
    fi
  done
}

function setup_timezone() {
  # Keep explicit TZ from environment or .env if already set
  if [[ -n "${TZ:-}" ]]; then
    export TZ
    log info "Using existing TZ: ${TZ}"
    return
  fi

  local detected_tz=""

  if [[ -f /etc/timezone ]]; then
    detected_tz=$(tr -d '[:space:]' < /etc/timezone)
  fi

  if [[ -z "$detected_tz" && -L /etc/localtime ]]; then
    local tz_path
    tz_path=$(readlink -f /etc/localtime 2>/dev/null || readlink /etc/localtime 2>/dev/null || true)
    if [[ "$tz_path" == *"/zoneinfo/"* ]]; then
      detected_tz="${tz_path##*/zoneinfo/}"
    fi
  fi

  if [[ -z "$detected_tz" ]] && command -v timedatectl >/dev/null 2>&1; then
    detected_tz=$(timedatectl show -p Timezone --value 2>/dev/null || true)
  fi

  if [[ -z "$detected_tz" ]]; then
    detected_tz="UTC"
    log warn "Unable to detect system timezone, falling back to UTC"
  fi

  export TZ="${detected_tz}"
  log info "Timezone set to: ${TZ}"
}

# Old compose mounted idmp_data at /var/lib/taos (data lived in volume/idmp/).
# New compose mounts idmp_data at /var/lib/taos/idmp (data at volume root).
function normalize_compose_project_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g; s/^-+//; s/-+$//'
}

function resolve_idmp_data_volume() {
  local container_name
  local volume_name
  local project_name
  local candidate

  for container_name in tdengine-idmp-backend tdengine-idmp-ui tdengine-idmp-ai tdengine-idmp; do
    volume_name=$(docker inspect -f '{{range .Mounts}}{{println .Name .Destination}}{{end}}' "$container_name" 2>/dev/null \
      | awk '$2 == "/var/lib/taos/idmp" || $2 == "/var/lib/taos" { print $1; exit }')
    if [[ -n "$volume_name" ]] && docker volume inspect "$volume_name" >/dev/null 2>&1; then
      echo "$volume_name"
      return 0
    fi
  done

  project_name="${COMPOSE_PROJECT_NAME:-$(basename "$(pwd)")}"
  project_name=$(normalize_compose_project_name "$project_name")
  for candidate in "${project_name}_idmp_data" "idmp_data"; do
    if docker volume inspect "$candidate" >/dev/null 2>&1; then
      echo "$candidate"
      return 0
    fi
  done

  volume_name=$(docker volume ls -q 2>/dev/null | grep -E '(^|_)idmp_data$' | head -n1 || true)
  if [[ -n "$volume_name" ]]; then
    echo "$volume_name"
    return 0
  fi

  return 1
}

function resolve_volume_helper_image() {
  local image_ref
  for image_ref in alpine:3.20 alpine:latest busybox:1.36 busybox:latest; do
    if docker image inspect "$image_ref" >/dev/null 2>&1; then
      echo "$image_ref"
      return 0
    fi
  done

  log info "Pulling alpine:3.20 for idmp_data volume migration..."
  if docker pull alpine:3.20 >/dev/null 2>&1; then
    echo "alpine:3.20"
    return 0
  fi

  for image_ref in \
    "tdengine/idmp-backend-ee:${IDMP_TAG:-latest}" \
    "tdengine/idmp-ai-ee:${IDMP_AI_TAG:-latest}"; do
    if docker image inspect "$image_ref" >/dev/null 2>&1; then
      echo "$image_ref"
      return 0
    fi
  done

  return 1
}

function migrate_idmp_data_volume_if_needed() {
  local volume_name
  local helper_image
  local probe_result
  local container_name
  local migrate_result

  volume_name=$(resolve_idmp_data_volume) || true
  if [[ -z "$volume_name" ]]; then
    return 0
  fi

  helper_image=$(resolve_volume_helper_image) || true
  if [[ -z "$helper_image" ]]; then
    log warn "Unable to find a helper image to inspect idmp_data; skipping volume migration check."
    return 0
  fi

  log info "Checking idmp_data volume layout (${volume_name})..."
  probe_result=$(docker run --rm --entrypoint sh -v "${volume_name}:/data:ro" "$helper_image" -c '
    if [ -d /data/idmp ] && [ -n "$(ls -A /data/idmp 2>/dev/null)" ]; then
      echo NEED_MIGRATE
    else
      echo OK
    fi
  ' 2>/dev/null || true)

  if [[ "$probe_result" != *NEED_MIGRATE* ]]; then
    return 0
  fi

  log info "Detected old idmp_data layout (volume previously mounted at /var/lib/taos)."
  log info "Migrating data to new layout (volume mounted at /var/lib/taos/idmp)..."

  for container_name in tdengine-idmp-backend tdengine-idmp-ui tdengine-idmp-ai tdengine-idmp; do
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$container_name"; then
      log info "Stopping ${container_name} for volume migration..."
      docker stop "$container_name" >/dev/null 2>&1 || true
    fi
  done

  local migrate_exit=0
  migrate_result=$(docker run --rm --entrypoint sh -v "${volume_name}:/data" "$helper_image" -c '
    set -e
    if [ ! -d /data/idmp ]; then
      echo MIGRATION_SKIP
      exit 0
    fi
    # Flatten volume/idmp/* -> volume/* for the new mount path.
    cd /data/idmp
    for f in * .[!.]* ..?*; do
      [ -e "$f" ] || continue
      if [ -e "/data/$f" ]; then
        echo "CONFLICT:$f"
        continue
      fi
      mv "$f" /data/
    done
    cd /data
    # Remove nested dir; keep any unmoved conflict leftovers inside if present
    if [ -z "$(ls -A /data/idmp 2>/dev/null)" ]; then
      rmdir /data/idmp 2>/dev/null || rm -rf /data/idmp
    else
      echo "WARN: leftover files remain under nested idmp/"
    fi
    echo MIGRATION_OK
  ' 2>&1) || migrate_exit=$?
  if [[ ${migrate_exit} -ne 0 ]]; then
    log error "Failed to migrate idmp_data volume (${volume_name})."
    log error "${migrate_result}"
    exit 1
  fi

  if [[ "$migrate_result" == *CONFLICT:* ]]; then
    log warn "Some files already existed at volume root and were kept; nested copies may remain."
    log warn "${migrate_result}"
  fi

  if [[ "$migrate_result" == *MIGRATION_OK* || "$migrate_result" == *MIGRATION_SKIP* ]]; then
    log info "idmp_data volume migration completed."
  else
    log error "Unexpected migration result for idmp_data volume."
    log error "${migrate_result}"
    exit 1
  fi
}

function start_services() {
  check_docker_compose
  select_compose_mode
  check_and_upgrade_images
  setup_url
  setup_license_server_addr
  ask_git_enable
  setup_timezone
  export IDMP_URL=${idmp_url}
  export TDA_LICENSE_SERVER_ADDR=${license_server_addr}

  if [[ $need_check_memory -eq 1 ]]; then
    check_docker_memory
  fi

  migrate_idmp_data_volume_if_needed
  remove_legacy_idmp_container

  local up_args=(-f "${compose_file}" up -d)
  if compose_services_exist; then
    log info "Existing services detected, forcing recreate..."
    up_args+=(--force-recreate)
  fi
  if [[ ${compose_supports_pull_policy} -eq 1 ]]; then
    up_args+=(--pull missing)
  fi

  log info "Starting services with ${compose_file}..."
  ${compose_cmd} "${up_args[@]}"
  ret=$?

  if [[ ${ret} -eq 0 ]]; then
    log info "Services started successfully!"
    log info "IDMP Web Console: ${idmp_url}"
    log info "License Server: ${license_server_addr}"
  else
    echo -e "${YELLOW}Failed to start services. Please check the logs.${NC}"
  fi
}

function compose_services_exist() {
  local names=()
  if [[ "$compose_file" == "docker-compose-tdgpt.yml" ]]; then
    names=("tdengine-tdgpt" "tdengine-tsdb" "tdengine-idmp-backend" "tdengine-idmp-ui" "tdengine-idmp-ai" "tdengine-idmp" "tdengine-model" "tdengine-cls")
  else
    names=("tdengine-tsdb" "tdengine-idmp-backend" "tdengine-idmp-ui" "tdengine-idmp-ai" "tdengine-idmp" "tdengine-cls")
  fi

  local name
  for name in "${names[@]}"; do
    if docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
      return 0
    fi
  done
  return 1
}

# Pre-split monolith container from older compose files; not in current compose.
function remove_legacy_idmp_container() {
  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "tdengine-idmp"; then
    log info "Removing legacy container tdengine-idmp..."
    docker rm -f tdengine-idmp >/dev/null 2>&1 || true
  fi
}

function detect_compose_file() {
  local detected_file=""
  local running_names=""

  if ! docker ps -q | grep -q .; then
    log warn "No running containers found"
    return 1
  fi

  running_names=$(docker ps --format '{{.Names}}' 2>/dev/null || true)

  if echo "$running_names" | grep -qx "tdengine-tdgpt"; then
    detected_file="docker-compose-tdgpt.yml"
    log info "Detected TDgpt containers, using: ${detected_file}"
  else
    if echo "$running_names" | grep -qxE 'tdengine-idmp-backend|tdengine-idmp-ui|tdengine-idmp-ai|tdengine-idmp|tdengine-tsdb|tdengine-cls'; then
      detected_file="docker-compose.yml"
      log info "Detected standard deployment containers, using: ${detected_file}"
    else
      log warn "No IDMP related containers found"
      return 1
    fi
  fi

  compose_file="$detected_file"
  return 0
}

function stop_services() {
  check_docker_compose

  if ! detect_compose_file; then
    log warn "Could not detect any running IDMP services."
    return
  fi

  log info "Stopping services with ${compose_file}..."
  while true; do
    printf "%b" "${GREEN_DARK}Do you want to clear data and logs? [y/N] ${NC}"
    read -r clean_volumes
    if [[ "$clean_volumes" =~ ^[Yy]$ ]]; then
      log info "Stopping services and cleaning volumes ..."
      ${compose_cmd} -f "${compose_file}" down -v
      ret=$?
      break
    elif [[ -z "$clean_volumes" || "$clean_volumes" =~ ^[Nn]$ ]]; then
      log info "Stopping services without cleaning volumes..."
      ${compose_cmd} -f "${compose_file}" down
      ret=$?
      break
    else
      echo -e "${YELLOW}Please enter y, n, or press Enter (default N).${NC}"
    fi
  done

  # New compose no longer defines tdengine-idmp; remove it explicitly on upgrade/stop.
  remove_legacy_idmp_container

  if [[ ${ret} -eq 0 ]]; then
    log info "Services stopped successfully!"
  else
    log error "Failed to stop services. Please check the logs."
  fi
}

function clean_environment() {
  local images=()
  local candidate_images=()
  local compose_files=()
  local container_names=()
  local volume_names=()
  local network_names=("taos_net")
  local compose_file_ref
  local container_name
  local volume_name
  local network_name
  local image_ref
  local existing_image
  local image_exists
  local ret

  check_docker_compose
  select_compose_mode

  compose_files=("$compose_file")
  container_names=("tdengine-tsdb" "tdengine-idmp-backend" "tdengine-idmp-ui" "tdengine-idmp-ai" "tdengine-idmp" "tdengine-cls")
  volume_names=("tsdb_data" "tsdb_log" "idmp_data" "idmp_log" "cls_data" "cls_log")
  candidate_images=(
    "tdengine/tsdb-ee:${TSDB_TAG:-latest}"
    "tdengine/idmp-backend-ee:${IDMP_TAG:-latest}"
    "tdengine/idmp-ui-ee:${IDMP_TAG:-latest}"
    "tdengine/idmp-ai-ee:${IDMP_AI_TAG:-latest}"
    "tdengine/cls:${CLS_TAG:-latest}"
  )

  if [[ "$compose_file" == "docker-compose-tdgpt.yml" ]]; then
    container_names=("tdengine-tdgpt" "tdengine-tsdb" "tdengine-idmp-backend" "tdengine-idmp-ui" "tdengine-idmp-ai" "tdengine-idmp" "tdengine-model" "tdengine-cls")
    volume_names+=("tdmodel_data" "tdmodel_mysql" "tdmodel_log")
    candidate_images+=(
      "tdengine/tdgpt-full:${TDGPT_TAG:-latest}"
      "tdengine/tdmodel:${TDMODEL_TAG:-latest}"
    )
  fi

  for container_name in "${container_names[@]}"; do
    image_ref=$(docker inspect --format='{{.Config.Image}}' "$container_name" 2>/dev/null)
    if [[ -n "$image_ref" ]]; then
      candidate_images+=("$image_ref")
    fi
  done

  for image_ref in "${candidate_images[@]}"; do
    [[ -z "$image_ref" ]] && continue
    if docker image inspect "$image_ref" >/dev/null 2>&1; then
      image_exists=0
      for existing_image in "${images[@]}"; do
        if [[ "$existing_image" == "$image_ref" ]]; then
          image_exists=1
          break
        fi
      done
      [[ ${image_exists} -eq 0 ]] && images+=("$image_ref")
    fi
  done

  echo -e "${YELLOW}This will remove containers, volumes, and images for the IDMP environment.${NC}"
  echo -e "${YELLOW}Compose files used:${NC}"
  for compose_file_ref in "${compose_files[@]}"; do
    echo "  - $compose_file_ref"
  done

  echo -e "${YELLOW}Containers managed by this environment:${NC}"
  for container_name in "${container_names[@]}"; do
    echo "  - $container_name"
  done

  echo -e "${YELLOW}Compose volumes to remove:${NC}"
  for volume_name in "${volume_names[@]}"; do
    echo "  - $volume_name"
  done

  echo -e "${YELLOW}Compose networks to remove:${NC}"
  for network_name in "${network_names[@]}"; do
    echo "  - $network_name"
  done

  if [[ ${#images[@]} -gt 0 ]]; then
    echo -e "${YELLOW}The following images will be removed:${NC}"
    for image_ref in "${images[@]}"; do
      echo "  - $image_ref"
    done
  else
    log info "No local IDMP images found to remove."
  fi

  while true; do
    printf "%b" "${GREEN_DARK}Do you want to clean the entire current environment? [y/N] ${NC}"
    read -r clean_choice
    if [[ "$clean_choice" =~ ^[Yy]$ ]]; then
      break
    elif [[ -z "$clean_choice" || "$clean_choice" =~ ^[Nn]$ ]]; then
      log info "Clean canceled."
      return
    else
      echo -e "${YELLOW}Please enter y, n, or press Enter (default N).${NC}"
    fi
  done

  for compose_file_ref in "${compose_files[@]}"; do
    log info "Removing services and volumes with ${compose_file_ref}..."
    ${compose_cmd} -f "${compose_file_ref}" down -v
    ret=$?
    if [[ ${ret} -ne 0 ]]; then
      log error "Failed to remove services and volumes with ${compose_file_ref}. Please check the logs."
      return
    fi
  done

  remove_legacy_idmp_container

  for image_ref in "${images[@]}"; do
    log info "Removing image ${image_ref}..."
    if ! docker image rm "$image_ref"; then
      log warn "Failed to remove image ${image_ref}, it may not exist or may still be in use."
    fi
  done

  log info "Current IDMP environment cleaned successfully!"
}

# main
parse_arguments "$@"

# Execute based on action
case "${action}" in
  start)
    start_services
    ;;
  stop)
    stop_services
    ;;
  clean)
    clean_environment
    ;;
  *)
    log error "Unknown action: ${action}"
    show_help
    exit 1
    ;;
esac
