#!/bin/bash

idmp_url="http://localhost:6042"
compose_file="docker-compose.yml"
compose_cmd=""
need_check_memory=0
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

  echo -e "\nOptions:"
  echo -e "  -h, --help\t\tShow this help message"

  echo -e "\nExamples:"
  echo -e "  $0 start\t# Start with interactive mode"
  echo -e "  $0 stop\t# Stop services"
}

function parse_arguments() {
  if [[ $# -eq 0 ]]; then
    log error "No command provided.\n"
    show_help
    exit 1
  fi

  while [[ $# -gt 0 ]]; do
    case $1 in
      start|stop)
        action="$1"
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
  if command -v docker-compose >/dev/null 2>&1; then
    compose_cmd="docker-compose"
    log info "Found docker-compose command"
  elif command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    compose_cmd="docker compose"
    log info "Found docker compose plugin"
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
    return 1
  fi
  local mem_gb=$((mem_limit / 1024 / 1024 / 1024))
  if (( mem_limit < MIN_DOCKER_MEMORY )); then
    log warn "Docker memory limit is less than 10GB (current: ${mem_gb}GB)."
    log warn "Please increase Docker's memory limit to at least 10GB and try again."
    exit 0
  else
    log info "Docker memory limit check passed: ${mem_gb}GB"
  fi
}

function select_compose_mode() {
  echo -e "${GREEN_DARK}Please select deployment mode:${NC}"
  echo "1) Standard deployment (TSDB Enterprise + IDMP) (docker-compose.yml)"
  echo "2) Full deployment (TSDB Enterprise + IDMP + TDgpt) (docker-compose-tdgpt.yml)"
  
  while true; do
    printf "%b" "${GREEN_DARK}Enter your choice [1-2]: ${NC}"
    read -r mode_choice
    
    case "$mode_choice" in
      1)
        compose_file="docker-compose.yml"
        need_check_memory=0
        log info "Selected: Standard deployment (TSDB Enterprise + IDMP)"
        break
        ;;
      2)
        compose_file="docker-compose-tdgpt.yml"
        need_check_memory=1
        log info "Selected: Full deployment (TSDB Enterprise + IDMP + TDgpt)"
        break
        ;;
      "")
        compose_file="docker-compose.yml"
        need_check_memory=0
        log info "Using default: Standard deployment (TSDB Enterprise + IDMP)"
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

function start_services() {
  check_docker_compose
  select_compose_mode
  setup_url
  export IDMP_URL=${idmp_url}

  if [[ $need_check_memory -eq 1 ]]; then
    check_docker_memory
  fi
  log info "Starting services with ${compose_file}..."
  ${compose_cmd} -f "${compose_file}" up -d
  ret=$?

  if [[ ${ret} -eq 0 ]]; then
    log info "Services started successfully!"
    log info "IDMP Web Console: ${idmp_url}"
  else
    echo -e "${YELLOW}Failed to start services. Please check the logs.${NC}"
  fi
}

function detect_compose_file() {
  local detected_file=""
  
  if ! docker ps -q | grep -q .; then
    log warn "No running containers found"
    return 1
  fi
  
  if docker ps --format "table {{.Names}}" | grep -q "tdengine-tdgpt"; then
    detected_file="docker-compose-tdgpt.yml"
    log info "Detected TDgpt containers, using: ${detected_file}"
  else
    if docker ps --format "table {{.Names}}" | grep -qE "tdengine-idmp|tdengine-tsdb"; then
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

  if [[ ${ret} -eq 0 ]]; then
    log info "Services stopped successfully!"
  else
    log error "Failed to stop services. Please check the logs."
  fi
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
  *)
    log error "Unknown action: ${action}"
    show_help
    exit 1
    ;;
esac