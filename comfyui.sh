#!/usr/bin/env bash
set -euo pipefail

# =========================
# Config (edit if needed)
# =========================
BASE_DIR="${BASE_DIR:-/workspace}"
COMFY_DIR="${COMFY_DIR:-$BASE_DIR/ComfyUI}"
VENV_DIR="${VENV_DIR:-$COMFY_DIR/venv}"
PORT="${PORT:-8188}"
HOST="${HOST:-0.0.0.0}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/comfyui.log}"
TMP_DIR="${TMP_DIR:-$BASE_DIR/tmp}"
PYTHON_BIN="${PYTHON_BIN:-python3}"

# =========================
# Helpers
# =========================
msg() { echo -e "\n[comfyui] $*\n"; }
die() { echo -e "\n[comfyui][ERROR] $*\n" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

ensure_dirs() {
  mkdir -p "$BASE_DIR" "$LOG_DIR" "$TMP_DIR"
}

ensure_git_clone() {
  if [ ! -d "$COMFY_DIR/.git" ]; then
    msg "Cloning ComfyUI into: $COMFY_DIR"
    rm -rf "$COMFY_DIR"
    git clone https://github.com/comfyanonymous/ComfyUI.git "$COMFY_DIR"
  else
    msg "ComfyUI repo exists: $COMFY_DIR"
  fi
}

ensure_venv() {
  if [ ! -d "$VENV_DIR" ]; then
    msg "Creating venv: $VENV_DIR"
    cd "$COMFY_DIR"
    "$PYTHON_BIN" -m venv "$VENV_DIR"
  else
    msg "venv exists: $VENV_DIR"
  fi
}

activate_venv() {
  # shellcheck disable=SC1090
  source "$VENV_DIR/bin/activate"
  python -V
  pip -V
}

install_requirements() {
  msg "Upgrading pip/wheel/setuptools"
  pip install --upgrade pip wheel setuptools

  msg "Installing ComfyUI requirements"
  cd "$COMFY_DIR"
  pip install --no-deps --no-cache-dir --require-hashes=false -r requirements.txt || \
pip install --no-cache-dir -r requirements.txt
}

export_temp() {
  export TMPDIR="$TMP_DIR"
  export TEMP="$TMP_DIR"
  export TMP="$TMP_DIR"
}

pid_file() {
  echo "$BASE_DIR/comfyui.pid"
}

is_running() {
  local pidf
  pidf="$(pid_file)"
  if [ -f "$pidf" ]; then
    local pid
    pid="$(cat "$pidf" || true)"
    if [ -n "${pid:-}" ] && kill -0 "$pid" >/dev/null 2>&1; then
      return 0
    fi
  fi
  return 1
}

stop_comfy() {
  local pidf pid
  pidf="$(pid_file)"
  if [ -f "$pidf" ]; then
    pid="$(cat "$pidf" || true)"
    if [ -n "${pid:-}" ] && kill -0 "$pid" >/dev/null 2>&1; then
      msg "Stopping ComfyUI (PID=$pid)"
      kill "$pid" || true
      sleep 1 || true
      if kill -0 "$pid" >/dev/null 2>&1; then
        msg "Force stopping ComfyUI (PID=$pid)"
        kill -9 "$pid" || true
      fi
    fi
    rm -f "$pidf"
  else
    msg "No PID file found. Nothing to stop."
  fi
}

start_comfy() {
  ensure_dirs
  ensure_git_clone
  ensure_venv
  activate_venv
  export_temp

  if is_running; then
    msg "ComfyUI already running. Use: $0 restart"
    return 0
  fi

  msg "Starting ComfyUI on ${HOST}:${PORT}"
  msg "Logs: $LOG_FILE"

  cd "$COMFY_DIR"
  # Start in background, write PID file
  nohup python main.py --listen "$HOST" --port "$PORT" >> "$LOG_FILE" 2>&1 &
  echo $! > "$(pid_file)"

  msg "Started. PID=$(cat "$(pid_file)")"
}

status_comfy() {
  if is_running; then
    msg "ComfyUI is RUNNING. PID=$(cat "$(pid_file)")  PORT=$PORT  DIR=$COMFY_DIR"
  else
    msg "ComfyUI is NOT running."
  fi
}

tail_logs() {
  msg "Tailing logs: $LOG_FILE (Ctrl+C to stop)"
  touch "$LOG_FILE"
  tail -n 200 -f "$LOG_FILE"
}

do_install() {
  ensure_dirs
  ensure_git_clone
  ensure_venv
  activate_venv
  export_temp
  install_requirements
  msg "Install complete."
}

do_update() {
  ensure_git_clone
  msg "Updating ComfyUI repo"
  cd "$COMFY_DIR"
  git pull --rebase
  msg "Update complete."
}

usage() {
  cat <<EOF
Usage: $0 <command>

Commands:
  install     Clone ComfyUI (if missing), create venv, install requirements
  update      git pull ComfyUI
  start       Start ComfyUI (background) + write PID + log to $LOG_FILE
  stop        Stop ComfyUI using PID file
  restart     Stop then start
  status      Show running status
  logs        Tail logs

Environment overrides (optional):
  BASE_DIR=/workspace
  COMFY_DIR=/workspace/ComfyUI
  PORT=8188
  HOST=0.0.0.0
EOF
}

main() {
  need_cmd git
  need_cmd "$PYTHON_BIN"

  local cmd="${1:-}"
  case "$cmd" in
    install)  do_install ;;
    update)   do_update ;;
    start)    start_comfy ;;
    stop)     stop_comfy ;;
    restart)  stop_comfy; start_comfy ;;
    status)   status_comfy ;;
    logs)     tail_logs ;;
    ""|-h|--help) usage ;;
    *) die "Unknown command: $cmd. Use -h for help." ;;
  esac
}

main "$@"
