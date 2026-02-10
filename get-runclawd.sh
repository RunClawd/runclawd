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
INSTALL_DIR="/opt/runclawd"

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

compose_up() {
  local compose
  compose="$(docker_compose_cmd)"
  log "Starting services with docker compose..."
  (cd "$INSTALL_DIR" && $compose up -d)
}

compose_logs() {
  local service="$1"
  local compose
  compose="$(docker_compose_cmd)"
  (cd "$INSTALL_DIR" && $compose logs --no-color "$service" 2>/dev/null || true)
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
  local web_term_password=""
  local tunnel_url=""

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

    if [[ -z "$web_term_password" ]]; then
      web_term_password="$(echo "$runclawd_logs" | sed -nE 's/.*Web Terminal Password:[[:space:]]*([^[:space:]]+).*/\1/p' | tail -n 1 || true)"
    fi

    if [[ -z "$tunnel_url" ]]; then
      local cloudflared_logs
      cloudflared_logs="$(compose_logs cloudflared | tail -n 500)"
      tunnel_url="$(extract_first_match "$cloudflared_logs" 'https://[a-z0-9-]+\.trycloudflare\.com' || true)"
    fi

    if [[ -n "$access_token" && -n "$web_term_password" && -n "$tunnel_url" ]]; then
      printf '%s\n' "$access_token" "$web_term_password" "$tunnel_url"
      return 0
    fi

    sleep 2
  done

  log "Timed out waiting for required values from logs."
  log "- Access Token: ${access_token:-<missing>}"
  log "- Web Terminal Password: ${web_term_password:-<missing>}"
  log "- Tunnel URL: ${tunnel_url:-<missing>}"
  return 1
}

print_result() {
  local access_token="$1"
  local web_term_password="$2"
  local tunnel_url="$3"

  cat <<EOF
=====================================================================
 🦞 OpenClaw is ready
=====================================================================

[1/4] Onboarding
  ${tunnel_url}/openclaw/?arg=onboard

[2/4] Web Terminal
  URL:      ${tunnel_url}/term/
  Username: openclaw
  Password: ${web_term_password}

[3/4] Gateway Dashboard
  ${tunnel_url}/?token=${access_token}

[4/4] Device approval (required)
  List devices:
    ${tunnel_url}/openclaw/?arg=devices&arg=list

  Approve a device:
    ${tunnel_url}/openclaw/?arg=devices&arg=approve&arg={device_id}

  Tip: open the "List devices" link, copy the returned device_id, then replace "{device_id}" in the approve link.

Notes:
  - If the URL is not reachable right away, wait a few minutes for DNS/route propagation and try again.
  - You must approve the device before you can access it.

EOF
}

main() {
  require_root
  ensure_deps
  install_docker

  if ! need_cmd docker; then
    die "Docker installation did not produce a usable 'docker' command."
  fi

  clone_or_update_repo
  compose_up

  local values
  if ! values="$(wait_for_values 300)"; then
    die "Failed to extract Access Token / Web Terminal Password / Tunnel URL from logs."
  fi

  local access_token
  local web_term_password
  local tunnel_url
  access_token="$(echo "$values" | sed -n '1p')"
  web_term_password="$(echo "$values" | sed -n '2p')"
  tunnel_url="$(echo "$values" | sed -n '3p')"

  print_result "$access_token" "$web_term_password" "$tunnel_url"
}

main "$@"
