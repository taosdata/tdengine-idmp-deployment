#!/bin/bash
# Migrate legacy idmp_data layout for IDMP 2.x Docker mounts.
#
# Old compose: idmp_data -> /var/lib/taos  (data under volume/idmp/)
# New compose: idmp_data -> /var/lib/taos/idmp  (data at volume root)
#
# Copies volume/idmp/* to volume root, keeps nested idmp/ for rollback,
# and writes marker .idmp_volume_layout_v2. If the root already has 2.x
# data (PREMATURE), moves it aside to _premature_2x_<stamp>/ first.
#
# Usage:
#   ./migrate-idmp-data.sh
#   ./migrate-idmp-data.sh --volume docker_idmp_data
#   ./migrate-idmp-data.sh --helper tdengine/idmp-backend-ee:2.0.0.11
#   ./migrate-idmp-data.sh --dry-run

set -euo pipefail

GREEN_DARK='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

volume_name=""
helper_image=""
dry_run=0
layout_marker=".idmp_volume_layout_v2"

function log() {
  case "$1" in
    info)  echo -e "${GREEN_DARK}[INFO]${NC} $2" ;;
    warn)  echo -e "${YELLOW}[WARN]${NC} $2" ;;
    error) echo -e "${RED}[ERROR]${NC} $2" ;;
  esac
}

function show_help() {
  cat <<'EOF'
Usage: migrate-idmp-data.sh [OPTIONS]

Flatten legacy idmp_data volume layout (volume/idmp/* -> volume root)
for IDMP 2.x mounts at /var/lib/taos/idmp.

Options:
  --volume NAME     Docker volume name (auto-detect if omitted)
  --helper IMAGE    Helper image for docker run (auto-detect if omitted)
  --dry-run         Only probe layout; do not modify the volume
  -h, --help        Show this help

Environment:
  IDMP_TAG / IDMP_AI_TAG   Used when resolving helper image tags
  COMPOSE_PROJECT_NAME     Used when resolving <project>_idmp_data

Examples:
  ./migrate-idmp-data.sh
  ./migrate-idmp-data.sh --volume myproj_idmp_data
  ./migrate-idmp-data.sh --dry-run
EOF
}

function normalize_compose_project_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g; s/^-+//; s/-+$//'
}

function resolve_idmp_data_volume() {
  local container_name
  local name
  local project_name
  local candidate

  for container_name in tdengine-idmp-backend tdengine-idmp-ui tdengine-idmp-ai tdengine-idmp; do
    name=$(docker inspect -f '{{range .Mounts}}{{println .Name .Destination}}{{end}}' "$container_name" 2>/dev/null \
      | awk '$2 == "/var/lib/taos/idmp" || $2 == "/var/lib/taos" { print $1; exit }')
    if [[ -n "$name" ]] && docker volume inspect "$name" >/dev/null 2>&1; then
      echo "$name"
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

  name=$(docker volume ls -q 2>/dev/null | grep -E '(^|_)idmp_data$' | head -n1 || true)
  if [[ -n "$name" ]]; then
    echo "$name"
    return 0
  fi

  return 1
}

function resolve_volume_helper_image() {
  local image_ref
  for image_ref in \
    "tdengine/idmp-backend-ee:${IDMP_TAG:-latest}" \
    "tdengine/idmp-ai-ee:${IDMP_AI_TAG:-latest}" \
    alpine:3.20 alpine:latest busybox:1.36 busybox:latest; do
    if docker image inspect "$image_ref" >/dev/null 2>&1; then
      echo "$image_ref"
      return 0
    fi
  done
  return 1
}

function parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --volume)
        [[ $# -ge 2 ]] || { log error "--volume requires a value"; exit 1; }
        volume_name="$2"
        shift 2
        ;;
      --volume=*)
        volume_name="${1#*=}"
        shift
        ;;
      --helper)
        [[ $# -ge 2 ]] || { log error "--helper requires a value"; exit 1; }
        helper_image="$2"
        shift 2
        ;;
      --helper=*)
        helper_image="${1#*=}"
        shift
        ;;
      --dry-run)
        dry_run=1
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

function main() {
  parse_args "$@"

  if ! command -v docker >/dev/null 2>&1; then
    log error "docker is required"
    exit 1
  fi

  if [[ -z "$volume_name" ]]; then
    volume_name=$(resolve_idmp_data_volume) || true
  fi
  if [[ -z "$volume_name" ]]; then
    log error "Unable to find idmp_data volume. Pass --volume NAME."
    exit 1
  fi
  if ! docker volume inspect "$volume_name" >/dev/null 2>&1; then
    log error "Docker volume not found: ${volume_name}"
    exit 1
  fi

  if [[ -z "$helper_image" ]]; then
    helper_image=$(resolve_volume_helper_image) || true
  fi
  if [[ -z "$helper_image" ]]; then
    log error "Unable to find a helper image. Pass --helper IMAGE (e.g. alpine:3.20),"
    log error "or ensure tdengine/idmp-backend-ee / alpine / busybox exists locally."
    exit 1
  fi
  if ! docker image inspect "$helper_image" >/dev/null 2>&1; then
    log error "Helper image not found locally: ${helper_image}"
    exit 1
  fi

  log info "Using volume: ${volume_name}"
  log info "Using helper image: ${helper_image}"
  log info "Checking idmp_data volume layout..."

  local probe_result
  probe_result=$(docker run --rm -u 0:0 --entrypoint sh -v "${volume_name}:/data:ro" "$helper_image" -c '
    marker="'"${layout_marker}"'"
    if [ -f "/data/${marker}" ]; then
      echo OK
      exit 0
    fi
    if [ ! -d /data/idmp ] || [ -z "$(ls -A /data/idmp 2>/dev/null)" ]; then
      echo OK
      exit 0
    fi
    echo NEED_MIGRATE
    cd /data
    for f in * .[!.]* ..?*; do
      [ -e "$f" ] || continue
      [ "$f" = "idmp" ] && continue
      [ "$f" = "'"${layout_marker}"'" ] && continue
      case "$f" in
        _premature_2x_*) continue ;;
      esac
      echo PREMATURE
      break
    done
  ') || {
    log error "Failed to probe volume layout (docker run failed)."
    exit 1
  }

  if [[ "$probe_result" != *NEED_MIGRATE* ]]; then
    log info "No migration needed (already flat, empty, or no nested idmp/ data)."
    exit 0
  fi

  log info "Detected old idmp_data layout (volume previously mounted at /var/lib/taos)."
  if [[ "$probe_result" == *PREMATURE* ]]; then
    log warn "Volume root already has data (likely 2.x started before migration)."
    log warn "Will move root files aside, then copy legacy nested idmp/ to volume root (keeping idmp/ for rollback)."
  else
    log info "Will copy nested idmp/ data to volume root (keeping nested idmp/ for rollback)."
  fi

  if [[ ${dry_run} -eq 1 ]]; then
    log info "Dry-run only; no changes made."
    exit 0
  fi

  local container_name
  for container_name in tdengine-idmp-backend tdengine-idmp-ui tdengine-idmp-ai tdengine-idmp; do
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$container_name"; then
      log info "Stopping ${container_name} for volume migration..."
      docker stop "$container_name" >/dev/null 2>&1 || true
    fi
  done

  local migrate_result
  local migrate_exit=0
  migrate_result=$(docker run --rm -u 0:0 --entrypoint sh -v "${volume_name}:/data" "$helper_image" -c '
    set -e
    marker="'"${layout_marker}"'"
    if [ -f "/data/${marker}" ]; then
      echo MIGRATION_SKIP
      exit 0
    fi
    if [ ! -d /data/idmp ]; then
      echo MIGRATION_SKIP
      exit 0
    fi

    premature=0
    cd /data
    for f in * .[!.]* ..?*; do
      [ -e "$f" ] || continue
      [ "$f" = "idmp" ] && continue
      [ "$f" = "'"${layout_marker}"'" ] && continue
      case "$f" in
        _premature_2x_*) continue ;;
      esac
      premature=1
      break
    done

    if [ "$premature" -eq 1 ]; then
      stamp=$(date +%Y%m%d-%H%M%S)
      aside="/data/_premature_2x_${stamp}"
      mkdir -p "$aside"
      cd /data
      for f in * .[!.]* ..?*; do
        [ -e "$f" ] || continue
        [ "$f" = "idmp" ] && continue
        case "$f" in
          _premature_2x_*) continue ;;
        esac
        mv "$f" "$aside/"
      done
      echo "ASIDE:$aside"
    fi

    cd /data/idmp
    for f in * .[!.]* ..?*; do
      [ -e "$f" ] || continue
      if [ -e "/data/$f" ]; then
        echo "CONFLICT:$f"
        rm -rf "/data/$f"
      fi
      if cp -a "$f" /data/ 2>/dev/null; then
        :
      else
        if [ -d "$f" ]; then
          cp -r "$f" /data/
        else
          cp "$f" /data/
        fi
      fi
    done
    printf "flat-copy\n" > "/data/${marker}"
    echo MIGRATION_OK
  ' 2>&1) || migrate_exit=$?

  if [[ ${migrate_exit} -ne 0 ]]; then
    log error "Failed to migrate idmp_data volume (${volume_name})."
    log error "${migrate_result}"
    log error "Original data remains under nested idmp/ for rollback."
    exit 1
  fi

  if [[ "$migrate_result" == *CONFLICT:* ]]; then
    log warn "Some root paths already existed and were replaced from nested idmp/."
    log warn "${migrate_result}"
  fi

  if [[ "$migrate_result" == *MIGRATION_OK* || "$migrate_result" == *MIGRATION_SKIP* ]]; then
    log info "idmp_data volume migration completed (nested idmp/ kept for rollback)."
    if [[ "$migrate_result" == *ASIDE:* ]]; then
      log info "Premature 2.x root data was moved aside (see ASIDE path in migration output)."
      echo "${migrate_result}" | grep '^ASIDE:' || true
    fi
    log info "Rollback tip: remount idmp_data at /var/lib/taos to use nested idmp/ again."
  else
    log error "Unexpected migration result for idmp_data volume."
    log error "${migrate_result}"
    exit 1
  fi
}

main "$@"
