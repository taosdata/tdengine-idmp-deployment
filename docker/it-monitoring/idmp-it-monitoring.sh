#!/bin/bash

idmp_url="http://localhost:6042"
compose_file="docker-compose-it-monitoring.yml"
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

function select_compose_mode() {
  echo -e "${GREEN_DARK}Please select deployment mode:${NC}"
  echo "1) Standard deployment (TSDB Enterprise + IDMP) (docker-compose-it-monitoring.yml)"
  echo "2) Full deployment (TSDB Enterprise + IDMP + TDgpt) (docker-compose-tdgpt.yml)"
  
  while true; do
    printf "%b" "${GREEN_DARK}Enter your choice [1-2]: ${NC}"
    read -r mode_choice
    
    case "$mode_choice" in
      1)
        compose_file="docker-compose-it-monitoring.yml"
        log info "Selected: Standard deployment (TSDB Enterprise + IDMP)"
        break
        ;;
      2)
        compose_file="docker-compose-tdgpt.yml"
        log info "Selected: Full deployment (TSDB Enterprise + IDMP + TDgpt)"
        break
        ;;
      "")
        compose_file="docker-compose-it-monitoring.yml"
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
    host_ip=$(ifconfig | awk '/^[a-zA-Z0-9]/ {iface=$1} /inet / && iface !~ /^(docker|br-|veth|lo)/ && $2!="127.0.0.1" {print $2}'| head -n1)
  elif command -v powershell.exe >/dev/null 2>&1; then
    host_ip=$(powershell.exe -NoProfile -Command "(Get-NetIPAddress -AddressFamily IPv4 | Where-Object { \$_.IPAddress -ne '127.0.0.1' -and \$_.PrefixOrigin -ne 'WellKnown' } | Select-Object -First 1).IPAddress" 2>/dev/null | tr -d '\r')
  elif command -v ipconfig >/dev/null 2>&1; then
    host_ip=$(ipconfig | grep -i 'IPv4' | grep -v '127.0.0.1' | head -n1 | awk -F': ' '{print $2}' | tr -d '\r ')
  else
    log warn "No IP detection command found. Using default URL."
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

function wait_for_tsdb() {
  local tsdb_url="http://localhost:6041"
  local max_retries=30
  local retry=0

  log info "Waiting for TSDB to be ready..."
  while [[ $retry -lt $max_retries ]]; do
    if curl -s -o /dev/null -w "%{http_code}" -u "root:taosdata" -d "show databases;" "${tsdb_url}/rest/sql" 2>/dev/null | grep -q "200"; then
      log info "TSDB is ready!"
      return 0
    fi
    retry=$((retry + 1))
    echo -n "."
    sleep 2
  done
  echo ""
  log error "TSDB failed to become ready after $((max_retries * 2)) seconds"
  return 1
}

function retrieve_and_inject_token() {
  local tsdb_url="http://localhost:6041"
  local username_file=".idmp_user_name"
  local password_file=".idmp_user_password"
  local token_cache_file=".idmp_token_value"

  # 如果没有临时文件，说明是 root 用户，无需获取 token
  if [[ ! -f "$username_file" ]] || [[ ! -f "$password_file" ]]; then
    log info "No custom user created, skipping token retrieval"
    return 0
  fi

  local username
  username=$(cat "$username_file")

  local token_name="${username}_token"
  local token=""

  # 检查 TDengine 中是否已存在该 token
  local show_resp
  show_resp=$(curl -s -u "root:taosdata" -d "SHOW TOKENS;" "${tsdb_url}/rest/sql" 2>/dev/null)
  local token_exists=0
  if echo "$show_resp" | grep -q "\"${token_name}\""; then
    token_exists=1
  fi

  if [[ "$token_exists" -eq 1 ]] && [[ -f "$token_cache_file" ]]; then
    # 重启场景：token 已存在且本地有缓存值，直接复用
    token=$(cat "$token_cache_file")
    log info "Reusing existing token for user: ${username} (restart detected)"
  else
    # 首次启动或缓存丢失：创建新 token
    if [[ "$token_exists" -eq 1 ]]; then
      # token 存在但缓存丢失，需要先删除再重建（无法从 SHOW TOKENS 获取值）
      log warn "Token ${token_name} exists but cached value is missing, re-creating..."
      curl -s -u "root:taosdata" -d "DROP TOKEN ${token_name};" "${tsdb_url}/rest/sql" >/dev/null 2>&1
    fi

    log info "Creating token for user: ${username}..."
    local response
    response=$(curl -s -u "root:taosdata" -d "CREATE TOKEN ${token_name} FROM USER ${username};" "${tsdb_url}/rest/sql" 2>/dev/null)

    # 从 CREATE TOKEN 响应中解析 token 值
    # 优先使用 python3/python，Windows 降级用 powershell，最后用 grep
    local python_cmd=""
    if command -v python3 >/dev/null 2>&1; then
      python_cmd="python3"
    elif command -v python >/dev/null 2>&1; then
      python_cmd="python"
    fi

    if [[ -n "$python_cmd" ]]; then
      token=$($python_cmd -c "
import json, sys
try:
    data = json.loads(sys.stdin.read())
    if data.get('code') == 0:
        cols = [c[0] for c in data.get('column_meta', [])]
        for row in data.get('data', []):
            if 'token' in cols:
                idx = cols.index('token')
                print(row[idx])
            elif len(row) > 0:
                print(row[0])
            break
except Exception:
    pass
" <<< "$response" 2>/dev/null)
    elif command -v powershell.exe >/dev/null 2>&1; then
      token=$(powershell.exe -NoProfile -Command "
        \$d = '${response}' | ConvertFrom-Json
        if (\$d.code -eq 0 -and \$d.data.Count -gt 0) {
          \$cols = \$d.column_meta | ForEach-Object { \$_[0] }
          \$idx = [array]::IndexOf(\$cols, 'token')
          if (\$idx -ge 0) { \$d.data[0][\$idx] } else { \$d.data[0][0] }
        }
      " 2>/dev/null | tr -d '\r')
    else
      # 最终降级：用 grep 从 JSON data 数组提取（格式: "data":[["token_value"]]）
      token=$(echo "$response" | grep -o '"data":\[\[\"[^"]*\"\]\]' | grep -o '\[\[\"[^"]*\"\]\]' | tr -d '[]"')
    fi

    if [[ -z "$token" ]]; then
      log error "Failed to create token for ${username}. CREATE TOKEN response: ${response}"
      rm -f "$username_file" "$password_file"
      return 1
    fi

    # 持久化保存 token 值，供重启时复用
    echo "$token" > "$token_cache_file"
    log info "Token created and cached for user: ${username}"
  fi

  # 将 token 注入到 application-external.yml
  if [[ -f "application-external.yml" ]]; then
    sed -i.bak "s/__TOKEN_PLACEHOLDER__/${token}/" application-external.yml
    rm -f application-external.yml.bak
    log info "Token injected into application-external.yml"
  else
    log error "application-external.yml not found!"
    rm -f "$username_file" "$password_file"
    return 1
  fi

  # 清理临时文件（保留 token_cache_file 供重启复用）
  rm -f "$username_file" "$password_file"
  return 0
}

function start_services() {
  check_docker_compose
#  select_compose_mode
  setup_url
  export IDMP_URL=${idmp_url}
  chmod +x ./generate-external-config.sh
  ./generate-external-config.sh
  ret=$?
  if [[ ${ret} -ne 0 ]]; then
    log error "Failed to generate config. Aborting."
    exit 1
  fi

  # 检查是否需要分步启动（非 root 用户需要先启动 TSDB 获取 token）
  if [[ -f ".idmp_user_name" ]]; then
    log info "Custom user detected, using split-start mode..."

    # 步骤 1: 只启动 TSDB
    log info "Step 1: Starting TSDB service..."
    ${compose_cmd} -f "${compose_file}" up -d tdengine-tsdb-it
    ret=$?
    if [[ ${ret} -ne 0 ]]; then
      log error "Failed to start TSDB service."
      exit 1
    fi

    # 步骤 2: 等待 TSDB 就绪
    if ! wait_for_tsdb; then
      log error "TSDB is not ready. Aborting."
      exit 1
    fi

    # 步骤 3: 获取 token 并注入配置
    if ! retrieve_and_inject_token; then
      log error "Failed to retrieve token. Aborting."
      exit 1
    fi

    # 步骤 4: 启动 IDMP
    log info "Step 2: Starting IDMP service..."
    ${compose_cmd} -f "${compose_file}" up -d tdengine-idmp-it
    ret=$?
  else
    # root 用户，直接启动所有服务
    log info "Starting all services with ${compose_file}..."
    ${compose_cmd} -f "${compose_file}" up -d
    ret=$?
  fi

  if [[ ${ret} -eq 0 ]]; then
    log info "Services started successfully!"
    log info "IDMP Web Console: ${idmp_url}"
  else
    log error "Failed to start services. Please check the logs."
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
      detected_file="docker-compose-it-monitoring.yml"
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
      # 清理缓存的 token 值和临时文件
      rm -f .idmp_token_value .idmp_user_name .idmp_user_password
      log info "Cleaned cached token and temp files."
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