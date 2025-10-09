#!/bin/bash

idmp_url="http://localhost:6042"
compose_file="docker-compose.yml"
compose_cmd=""

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
        log info "Selected: Standard deployment (TSDB Enterprise + IDMP)"
        break
        ;;
      2)
        compose_file="docker-compose-tdgpt.yml"
        log info "Selected: Full deployment (TSDB Enterprise + IDMP + TDgpt)"
        break
        ;;
      "")
        compose_file="docker-compose.yml"
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
    printf "%b" "${GREEN_DARK}Do you want to use this URL to access IDMP web console? ${idmp_url} [Y/n]: ${NC}"
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

check_docker_compose
select_compose_mode
setup_url
export IDMP_URL=${idmp_url}

log info "Starting services with ${compose_file}..."
${compose_cmd} -f "${compose_file}" up -d
ret=$?

if [[ $ret -eq 0 ]]; then
  log info "Services started successfully!"
  log info "IDMP Web Console: ${idmp_url}"
else
  echo -e "${YELLOW}Failed to start services. Please check the logs.${NC}"
fi