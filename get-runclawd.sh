#!/usr/bin/env sh
if [ -z "${BASH_VERSION:-}" ]; then
  if command -v bash >/dev/null 2>&1; then
    exec bash "$0" "$@"
  fi
  printf '%s\n' "ERROR: bash is required to run this installer." >&2
  exit 1
fi

set -euo pipefail

REPO_SSH_URL="https://github.com/RunClawd/runclawd.git"
DEFAULT_INSTALL_DIR="/opt/runclawd"
INSTALL_DIR="$DEFAULT_INSTALL_DIR"

LOCAL_MODE=0
if [[ "${RUNCLAWD_LOCAL:-}" = "1" ]]; then
  LOCAL_MODE=1
fi
BUILD_MODE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local)
      LOCAL_MODE=1
      shift
      ;;
    --build)
      BUILD_MODE=1
      shift
      ;;
    *)
      break
      ;;
  esac
done

if (( LOCAL_MODE )); then
  INSTALL_DIR="$(pwd)"
fi

USE_TUNNEL_TOKEN=0
if [[ -n "${CF_TUNNEL_TOKEN:-}" ]]; then
  USE_TUNNEL_TOKEN=1
fi

compose_base_args() {
  if (( USE_TUNNEL_TOKEN )); then
    printf '%s\n' "-f" "docker-compose.yaml" "-f" "docker-compose.tunnel.yaml"
  else
    printf '%s\n' "-f" "docker-compose.yaml"
  fi
}

log() {
  printf '%s\n' "$*" >&2
}

die() {
  log "ERROR: $*"
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "Please run as root (e.g. sudo bash get-runclawd.sh)."
  fi
}

install_pkg() {
  local pkg="$1"

  if need_cmd apt-get; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y "$pkg"
    return 0
  fi

  if need_cmd dnf; then
    dnf install -y "$pkg"
    return 0
  fi

  if need_cmd yum; then
    yum install -y "$pkg"
    return 0
  fi

  if need_cmd apk; then
    apk add --no-cache "$pkg"
    return 0
  fi

  if need_cmd pacman; then
    pacman -Sy --noconfirm "$pkg"
    return 0
  fi

  if need_cmd zypper; then
    zypper --non-interactive in -y "$pkg"
    return 0
  fi

  die "Unsupported package manager. Please install '$pkg' manually."
}

ensure_deps() {
  if ! need_cmd curl; then
    log "Installing curl..."
    install_pkg curl
  fi

  if ! need_cmd git; then
    log "Installing git..."
    install_pkg git
  fi

  if ! need_cmd ssh; then
    log "Installing ssh client..."
    if need_cmd apt-get; then
      install_pkg openssh-client
    elif need_cmd apk; then
      install_pkg openssh-client
    else
      install_pkg openssh
    fi
  fi
}

install_docker() {
  if need_cmd docker; then
    return 0
  fi
  log "Installing Docker using get.docker.com..."
  curl -fsSL https://get.docker.com | sh
}

docker_compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    echo "docker compose"
    return 0
  fi
  if need_cmd docker-compose; then
    echo "docker-compose"
    return 0
  fi
  die "Docker Compose not found. Please install docker compose plugin."
}

clone_or_update_repo() {
  mkdir -p "$(dirname "$INSTALL_DIR")"

  if [[ -d "$INSTALL_DIR/.git" ]]; then
    log "Updating repo in $INSTALL_DIR..."
    git -C "$INSTALL_DIR" fetch --all --prune
    git -C "$INSTALL_DIR" pull --rebase
    return 0
  fi

  if [[ -e "$INSTALL_DIR" && ! -d "$INSTALL_DIR" ]]; then
    die "$INSTALL_DIR exists and is not a directory."
  fi

  if [[ -d "$INSTALL_DIR" && ! -d "$INSTALL_DIR/.git" ]]; then
    die "$INSTALL_DIR exists but is not a git repo. Please remove it or choose a different install dir."
  fi

  log "Cloning $REPO_SSH_URL into $INSTALL_DIR..."
  git clone "$REPO_SSH_URL" "$INSTALL_DIR"
}

ensure_cloudflared_config() {
  if (( ! USE_TUNNEL_TOKEN )); then
    return 0
  fi

  local dir
  dir="$INSTALL_DIR/cloudflared"
  mkdir -p "$dir"

  if [[ -n "${SERVICE_FQDN_OPENCLAW:-}" ]]; then
    cat >"$dir/config.yml" <<EOF
ingress:
  - hostname: ${SERVICE_FQDN_OPENCLAW}
    service: http://caddy:80
  - service: http_status:404
EOF
  else
    cat >"$dir/config.yml" <<EOF
ingress:
  - service: http://caddy:80
  - service: http_status:404
EOF
  fi
}

compose_up() {
  local compose
  compose="$(docker_compose_cmd)"
  log "Starting services with docker compose..."
  local -a args
  mapfile -t args < <(compose_base_args)
  if (( BUILD_MODE )); then
    log "Rebuilding runclawd image (docker compose build runclawd)..."
    (cd "$INSTALL_DIR" && CF_TUNNEL_TOKEN="${CF_TUNNEL_TOKEN:-}" $compose "${args[@]}" build runclawd)
  fi
  (cd "$INSTALL_DIR" && CF_TUNNEL_TOKEN="${CF_TUNNEL_TOKEN:-}" $compose "${args[@]}" up -d)
}

compose_logs() {
  local service="$1"
  local compose
  compose="$(docker_compose_cmd)"
  local -a args
  mapfile -t args < <(compose_base_args)
  (cd "$INSTALL_DIR" && $compose "${args[@]}" logs --no-color "$service" 2>/dev/null || true)
}

extract_first_match() {
  local input="$1"
  local regex="$2"
  if [[ -z "$input" ]]; then
    return 1
  fi
  echo "$input" | grep -Eo "$regex" | head -n 1
}

wait_for_values() {
  local timeout_seconds="$1"
  local start_ts
  start_ts="$(date +%s)"

  local access_token=""
  local basic_auth_password=""
  local tunnel_url=""

  if (( USE_TUNNEL_TOKEN )); then
    if [[ -n "${SERVICE_FQDN_OPENCLAW:-}" ]]; then
      tunnel_url="https://${SERVICE_FQDN_OPENCLAW}"
    fi
  fi

  while true; do
    local now_ts
    now_ts="$(date +%s)"
    if (( now_ts - start_ts > timeout_seconds )); then
      break
    fi

    local runclawd_logs
    runclawd_logs="$(compose_logs runclawd | tail -n 500)"

    if [[ -z "$access_token" ]]; then
      access_token="$(echo "$runclawd_logs" | sed -nE 's/.*Access Token:[[:space:]]*([^[:space:]]+).*/\1/p' | tail -n 1 || true)"
    fi

    if [[ -z "$basic_auth_password" ]]; then
      local caddy_logs
      caddy_logs="$(compose_logs caddy | tail -n 500)"
      basic_auth_password="$(echo "$caddy_logs" | sed -nE 's/.*Basic Auth Password:[[:space:]]*([^[:space:]]+).*/\1/p' | tail -n 1 || true)"
    fi

    if (( USE_TUNNEL_TOKEN )); then
      true
    else
      if [[ -z "$tunnel_url" ]]; then
        local cloudflared_logs
        cloudflared_logs="$(compose_logs cloudflared | tail -n 500)"
        tunnel_url="$(extract_first_match "$cloudflared_logs" 'https://[a-z0-9-]+\.trycloudflare\.com' || true)"
      fi
    fi

    if [[ -n "$access_token" && -n "$basic_auth_password" && ( $USE_TUNNEL_TOKEN -eq 1 || -n "$tunnel_url" ) ]]; then
      printf '%s\n' "$access_token" "$basic_auth_password" "$tunnel_url"
      return 0
    fi

    sleep 2
  done

  log "Timed out waiting for required values from logs."
  log "- Access Token: ${access_token:-<missing>}"
  log "- Basic Auth Password: ${basic_auth_password:-<missing>}"
  if (( USE_TUNNEL_TOKEN )); then
    log "- Tunnel URL: ${tunnel_url:-<skipped>}"
  else
    log "- Tunnel URL: ${tunnel_url:-<missing>}"
  fi
  return 1
}

print_result() {
  local access_token="$1"
  local basic_auth_password="$2"
  local tunnel_url="$3"

  if (( USE_TUNNEL_TOKEN )); then
    cat <<EOF
=====================================================================
 🦞 OpenClaw is ready
=====================================================================

[1/2] Basic Auth
  Basic Auth Username: runclawd
  Basic Auth Password: ${basic_auth_password}

[2/2] Public access (Cloudflare Tunnel)
  CF_TUNNEL_TOKEN is set. Configure a Public Hostname / Route in Cloudflare for this tunnel.
EOF

    if [[ -n "$tunnel_url" ]]; then
      cat <<EOF
  Public URL: ${tunnel_url}
  Then access:
    ${tunnel_url}/openclaw/?arg=onboard
    ${tunnel_url}/term/
    ${tunnel_url}/?token=${access_token}

Notes:
  - All HTTP endpoints are protected by Caddy HTTP Basic Auth (including /openclaw onboarding routes).

EOF
    else
      cat <<EOF
  Then access:
    /openclaw/?arg=onboard
    /term/
    /?token=${access_token}

Notes:
  - All HTTP endpoints are protected by Caddy HTTP Basic Auth (including /openclaw onboarding routes).

EOF
    fi

    return 0
  fi

  cat <<EOF
=====================================================================
 🦞 OpenClaw is ready
=====================================================================

[1/5] Basic Auth
  Basic Auth Username: runclawd
  Basic Auth Password: ${basic_auth_password}

[2/5] Onboarding
  ${tunnel_url}/openclaw/?arg=onboard

[3/5] Web Terminal
  ${tunnel_url}/term/

[4/5] Gateway Dashboard
  ${tunnel_url}/?token=${access_token}

[5/5] Device approval (required)
  List devices:
    ${tunnel_url}/openclaw/?arg=devices&arg=list

  Approve a device:
    ${tunnel_url}/openclaw/?arg=devices&arg=approve&arg={request_id}

  Tip: open the "List devices" link, find the pending request (UUID), copy its ID, then replace "{request_id}" in the approve link.

Notes:
  - If the URL is not reachable right away, wait a few minutes for DNS/route propagation and try again.
  - You must approve the device before you can access it.
  - All HTTP endpoints are protected by Caddy HTTP Basic Auth (including /openclaw onboarding routes).

EOF
}

main() {
  if (( ! LOCAL_MODE )); then
    require_root
    ensure_deps
    install_docker
  fi

  if ! need_cmd docker; then
    die "Docker installation did not produce a usable 'docker' command."
  fi

  if (( ! LOCAL_MODE )); then
    clone_or_update_repo
  else
    if [[ ! -f "$INSTALL_DIR/docker-compose.yaml" ]]; then
      die "Local mode expects docker-compose.yaml in current directory."
    fi
  fi
  ensure_cloudflared_config
  compose_up

  local values
  if ! values="$(wait_for_values 300)"; then
    die "Failed to extract Access Token / Basic Auth Password / Tunnel URL from logs."
  fi

  local access_token
  local basic_auth_password
  local tunnel_url
  access_token="$(echo "$values" | sed -n '1p')"
  basic_auth_password="$(echo "$values" | sed -n '2p')"
  tunnel_url="$(echo "$values" | sed -n '3p')"

  print_result "$access_token" "$basic_auth_password" "$tunnel_url"
}

main "$@"
