#!/usr/bin/env bash
set -u

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_URL="http://127.0.0.1:8765"
RUNTIME_DIR="$APP_DIR/.runtime"
LOG_DIR="$RUNTIME_DIR/logs"
LOCAL_NODE="$RUNTIME_DIR/node/bin/node"
NODE_PID=""
OLLAMA_PID=""

mkdir -p "$LOG_DIR"

find_ollama() {
  if command -v ollama >/dev/null 2>&1; then command -v ollama; return 0; fi
  for candidate in \
    /usr/local/bin/ollama \
    /opt/homebrew/bin/ollama \
    "$HOME/.ollama/bin/ollama" \
    /Applications/Ollama.app/Contents/Resources/ollama
  do
    if [ -x "$candidate" ]; then printf '%s\n' "$candidate"; return 0; fi
  done
  return 1
}

chat_is_ready() {
  curl -fsS --max-time 1 "$APP_URL/api/status" 2>/dev/null | grep -q 'ia-local-mini-chat'
}

ollama_is_ready() {
  curl -fsS --max-time 2 'http://127.0.0.1:11434/api/tags' >/dev/null 2>&1
}

cleanup() {
  trap - EXIT INT TERM
  if [ -n "$NODE_PID" ] && kill -0 "$NODE_PID" 2>/dev/null; then kill "$NODE_PID" 2>/dev/null || true; fi
  if [ -n "$OLLAMA_PID" ] && kill -0 "$OLLAMA_PID" 2>/dev/null; then kill "$OLLAMA_PID" 2>/dev/null || true; fi
}
trap cleanup EXIT INT TERM

if [ -x "$LOCAL_NODE" ]; then
  NODE_BIN="$LOCAL_NODE"
elif command -v node >/dev/null 2>&1; then
  NODE_BIN="$(command -v node)"
else
  echo 'No encontré Node.js. Ejecutá: bash instalar-mac-linux.sh' >&2
  exit 1
fi

OLLAMA_BIN="$(find_ollama || true)"
if [ -z "$OLLAMA_BIN" ]; then
  echo 'No encontré Ollama. Ejecutá: bash instalar-mac-linux.sh' >&2
  exit 1
fi

if ! ollama_is_ready; then
  "$OLLAMA_BIN" serve >"$LOG_DIR/ollama.log" 2>&1 &
  OLLAMA_PID=$!
  for _ in $(seq 1 80); do
    sleep 0.25
    if ollama_is_ready; then break; fi
  done
  if ! ollama_is_ready; then
    echo "Ollama no pudo iniciar. Revisá $LOG_DIR/ollama.log" >&2
    exit 1
  fi
fi

if chat_is_ready; then
  NODE_PID=""
else
  "$NODE_BIN" "$APP_DIR/server.js" >"$LOG_DIR/server.log" 2>&1 &
  NODE_PID=$!
  for _ in $(seq 1 60); do
    sleep 0.25
    if chat_is_ready; then break; fi
    if ! kill -0 "$NODE_PID" 2>/dev/null; then break; fi
  done
  if ! chat_is_ready; then
    echo "IA Local no pudo iniciar. Revisá $LOG_DIR/server.log" >&2
    exit 1
  fi
fi

case "$(uname -s)" in
  Darwin)
    if [ -d '/Applications/Google Chrome.app' ]; then
      open -na 'Google Chrome' --args "--app=$APP_URL" >/dev/null 2>&1
    else
      open "$APP_URL" >/dev/null 2>&1
    fi
    ;;
  *)
    BROWSER_BIN=""
    for browser in google-chrome-stable google-chrome chromium chromium-browser; do
      if command -v "$browser" >/dev/null 2>&1; then BROWSER_BIN="$(command -v "$browser")"; break; fi
    done
    if [ -n "$BROWSER_BIN" ]; then
      nohup "$BROWSER_BIN" "--app=$APP_URL" >"$LOG_DIR/browser.log" 2>&1 &
    elif command -v xdg-open >/dev/null 2>&1; then
      nohup xdg-open "$APP_URL" >"$LOG_DIR/browser.log" 2>&1 &
    else
      echo "Abrí $APP_URL en tu navegador."
    fi
    ;;
esac

if [ -n "$NODE_PID" ]; then
  wait "$NODE_PID" 2>/dev/null || true
fi
