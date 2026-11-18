#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNTIME_DIR="$APP_DIR/.runtime"
NODE_DIR="$RUNTIME_DIR/node"
MODELS_FILE="$APP_DIR/models.txt"
TEMP_DIR="${TMPDIR:-/tmp}/ia-local-install-$$"
SKIP_MODELS=0
NO_LAUNCH=0
FORCE_RUNTIME=0
OLLAMA_WAS_RUNNING=0
OLLAMA_INSTALL_PID=""

for argument in "$@"; do
  case "$argument" in
    --skip-models) SKIP_MODELS=1 ;;
    --no-launch) NO_LAUNCH=1 ;;
    --force-runtime) FORCE_RUNTIME=1 ;;
    *) echo "Parámetro desconocido: $argument" >&2; exit 2 ;;
  esac
done

step() { printf '\n\033[36m==> %s\033[0m\n' "$1"; }
success() { printf '\033[32m%s\033[0m\n' "$1"; }

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

ollama_is_ready() {
  curl -fsS --max-time 2 'http://127.0.0.1:11434/api/tags' >/dev/null 2>&1
}

cleanup() {
  if [ -n "$OLLAMA_INSTALL_PID" ] && kill -0 "$OLLAMA_INSTALL_PID" 2>/dev/null; then
    kill "$OLLAMA_INSTALL_PID" 2>/dev/null || true
  fi
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT INT TERM

stop_temporary_ollama() {
  if [ "$OLLAMA_WAS_RUNNING" -eq 1 ]; then return; fi
  if [ -n "$OLLAMA_INSTALL_PID" ] && kill -0 "$OLLAMA_INSTALL_PID" 2>/dev/null; then
    kill "$OLLAMA_INSTALL_PID" 2>/dev/null || true
    wait "$OLLAMA_INSTALL_PID" 2>/dev/null || true
    OLLAMA_INSTALL_PID=""
    return
  fi
  if command -v pkill >/dev/null 2>&1; then
    pkill -f '[o]llama serve' 2>/dev/null || true
    if [ "$(uname -s)" = 'Darwin' ]; then pkill -x Ollama 2>/dev/null || true; fi
  fi
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Falta el comando requerido: $1" >&2
    exit 1
  fi
}

run_as_root() {
  if [ "$(id -u)" -eq 0 ]; then "$@"
  elif command -v sudo >/dev/null 2>&1; then sudo "$@"
  else echo 'Esta instalación necesita sudo para agregar herramientas básicas.' >&2; exit 1
  fi
}

bootstrap_linux_tools() {
  if [ "$(uname -s)" != 'Linux' ]; then return; fi
  if command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1; then return; fi
  step 'Instalando herramientas básicas del sistema'
  if command -v apt-get >/dev/null 2>&1; then
    run_as_root apt-get update
    run_as_root apt-get install -y curl ca-certificates tar
  elif command -v dnf >/dev/null 2>&1; then
    run_as_root dnf install -y curl ca-certificates tar
  elif command -v pacman >/dev/null 2>&1; then
    run_as_root pacman -Sy --needed --noconfirm curl ca-certificates tar
  elif command -v zypper >/dev/null 2>&1; then
    run_as_root zypper --non-interactive install curl ca-certificates tar
  else
    echo 'No encontré curl/tar ni un gestor de paquetes compatible.' >&2
    exit 1
  fi
}

install_portable_node() {
  if [ -x "$NODE_DIR/bin/node" ] && [ "$FORCE_RUNTIME" -eq 0 ]; then
    success "Node local ya está instalado: $($NODE_DIR/bin/node --version)"
    return
  fi

  step 'Descargando Node.js LTS local'
  local system machine platform architecture index_json version archive base_url archive_path checksums expected actual extract_dir extracted
  system="$(uname -s)"
  machine="$(uname -m)"
  case "$system" in
    Darwin) platform='darwin' ;;
    Linux) platform='linux' ;;
    *) echo "Sistema no compatible: $system" >&2; exit 1 ;;
  esac
  case "$machine" in
    arm64|aarch64) architecture='arm64' ;;
    x86_64|amd64) architecture='x64' ;;
    *) echo "Arquitectura no compatible: $machine" >&2; exit 1 ;;
  esac

  index_json="$(curl -fsSL 'https://nodejs.org/dist/index.json')"
  version="$(printf '%s\n' "$index_json" | awk -F'"' '/"lts":[[:space:]]*"/{for(i=1;i<=NF;i++){if($i=="version"){print $(i+2); exit}}}')"
  if [ -z "$version" ]; then echo 'No pude determinar la versión LTS actual de Node.js.' >&2; exit 1; fi

  archive="node-$version-$platform-$architecture.tar.gz"
  base_url="https://nodejs.org/dist/$version"
  archive_path="$TEMP_DIR/$archive"
  curl -fL --progress-bar "$base_url/$archive" -o "$archive_path"
  checksums="$(curl -fsSL "$base_url/SHASUMS256.txt")"
  expected="$(printf '%s\n' "$checksums" | awk -v file="$archive" '$2==file {print $1; exit}')"
  if [ -z "$expected" ]; then echo 'No pude leer el checksum oficial de Node.js.' >&2; exit 1; fi

  if command -v shasum >/dev/null 2>&1; then actual="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
  else actual="$(sha256sum "$archive_path" | awk '{print $1}')"; fi
  if [ "$actual" != "$expected" ]; then echo 'El checksum de Node.js no coincide.' >&2; exit 1; fi

  extract_dir="$TEMP_DIR/node-extract"
  mkdir -p "$extract_dir" "$RUNTIME_DIR"
  tar -xzf "$archive_path" -C "$extract_dir"
  extracted="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  if [ -z "$extracted" ]; then echo 'El archivo de Node.js no contiene la carpeta esperada.' >&2; exit 1; fi
  case "$NODE_DIR" in "$APP_DIR/.runtime/node") ;; *) echo 'Ruta de runtime insegura.' >&2; exit 1;; esac
  rm -rf "$NODE_DIR"
  mv "$extracted" "$NODE_DIR"
  if command -v xattr >/dev/null 2>&1; then xattr -dr com.apple.quarantine "$NODE_DIR" 2>/dev/null || true; fi
  success "Node $version instalado dentro del proyecto."
}

install_node_dependencies() {
  step 'Instalando dependencias de IA Local'
  (cd "$APP_DIR" && PATH="$NODE_DIR/bin:$PATH" "$NODE_DIR/bin/npm" ci --omit=dev --no-audit --no-fund)
}

install_ollama_if_missing() {
  local existing installer
  existing="$(find_ollama || true)"
  if [ -n "$existing" ]; then success "Ollama ya está instalado: $existing"; return; fi

  step 'Instalando Ollama desde el instalador oficial'
  installer="$TEMP_DIR/ollama-install.sh"
  curl -fsSL 'https://ollama.com/install.sh' -o "$installer"
  sh "$installer"
  if [ -z "$(find_ollama || true)" ]; then echo 'Ollama terminó de instalarse, pero no encontré el ejecutable.' >&2; exit 1; fi
}

disable_linux_ollama_service() {
  if [ "$(uname -s)" != 'Linux' ] || ! command -v systemctl >/dev/null 2>&1; then return; fi
  if systemctl list-unit-files ollama.service >/dev/null 2>&1; then
    step 'Desactivando el inicio automático de Ollama'
    if command -v sudo >/dev/null 2>&1; then sudo systemctl disable --now ollama.service || true
    else systemctl disable --now ollama.service || true; fi
  fi
}

ensure_ollama_server() {
  local ollama_bin
  ollama_bin="$(find_ollama)"
  if ollama_is_ready; then return; fi
  step 'Iniciando Ollama para descargar los modelos'
  mkdir -p "$RUNTIME_DIR/logs"
  "$ollama_bin" serve >"$RUNTIME_DIR/logs/ollama-install.log" 2>&1 &
  OLLAMA_INSTALL_PID=$!
  for _ in $(seq 1 80); do sleep 0.25; if ollama_is_ready; then return; fi; done
  echo "Ollama no pudo iniciar. Revisá $RUNTIME_DIR/logs/ollama-install.log" >&2
  exit 1
}

install_models() {
  local ollama_bin model
  if [ "$SKIP_MODELS" -eq 1 ]; then echo 'Descarga de modelos omitida por parámetro.'; return; fi
  if [ ! -f "$MODELS_FILE" ]; then echo 'No encontré models.txt.' >&2; exit 1; fi
  ollama_bin="$(find_ollama)"
  while IFS= read -r model || [ -n "$model" ]; do
    model="${model%%#*}"
    model="$(printf '%s' "$model" | xargs)"
    if [ -z "$model" ]; then continue; fi
    step "Descargando modelo $model"
    "$ollama_bin" pull "$model"
  done < "$MODELS_FILE"
}

create_mac_icon() {
  local bundle="$1" preview iconset source size
  if ! command -v qlmanage >/dev/null 2>&1 || ! command -v iconutil >/dev/null 2>&1; then return; fi
  preview="$TEMP_DIR/icon-preview"
  iconset="$TEMP_DIR/IA-Local.iconset"
  mkdir -p "$preview" "$iconset"
  qlmanage -t -s 1024 -o "$preview" "$APP_DIR/ai-icon.svg" >/dev/null 2>&1 || return
  source="$preview/ai-icon.svg.png"
  if [ ! -f "$source" ]; then return; fi
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$source" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    sips -z "$((size * 2))" "$((size * 2))" "$source" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$iconset" -o "$bundle/Contents/Resources/IA-Local.icns" >/dev/null 2>&1 || true
}

install_mac_launcher() {
  local bundle="$HOME/Applications/IA Local.app"
  step 'Creando IA Local.app'
  mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
  printf '%s\n' "$APP_DIR" > "$bundle/Contents/Resources/project-path"
  cat > "$bundle/Contents/MacOS/IA Local" <<'LAUNCHER'
#!/usr/bin/env bash
BUNDLE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$(cat "$BUNDLE_DIR/Resources/project-path")"
exec "$APP_DIR/iniciar-chat.sh"
LAUNCHER
  chmod +x "$bundle/Contents/MacOS/IA Local"
  cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDisplayName</key><string>IA Local</string>
  <key>CFBundleExecutable</key><string>IA Local</string>
  <key>CFBundleIdentifier</key><string>com.ialocal.chat</string>
  <key>CFBundleIconFile</key><string>IA-Local</string>
  <key>CFBundleName</key><string>IA Local</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
  create_mac_icon "$bundle"
  touch "$bundle"
}

install_linux_launcher() {
  local bin_dir="$HOME/.local/bin" applications_dir="$HOME/.local/share/applications" launcher="$HOME/.local/bin/ia-local"
  step 'Creando acceso de aplicaciones para Linux'
  mkdir -p "$bin_dir" "$applications_dir"
  printf '#!/usr/bin/env bash\nexec %q/iniciar-chat.sh\n' "$APP_DIR" > "$launcher"
  chmod +x "$launcher"
  cat > "$applications_dir/ia-local.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=IA Local
Comment=Chat local con Ollama
Exec=$launcher
Icon=$APP_DIR/ai-icon.svg
Terminal=false
Categories=Utility;Development;
DESKTOP
  chmod +x "$applications_dir/ia-local.desktop"
  if command -v update-desktop-database >/dev/null 2>&1; then update-desktop-database "$applications_dir" >/dev/null 2>&1 || true; fi
}

bootstrap_linux_tools
require_command curl
require_command tar
mkdir -p "$TEMP_DIR" "$RUNTIME_DIR"
printf '\033[35mInstalador de IA Local para macOS/Linux\033[0m\nProyecto: %s\n' "$APP_DIR"
if ollama_is_ready; then OLLAMA_WAS_RUNNING=1; fi

install_portable_node
install_node_dependencies
install_ollama_if_missing
disable_linux_ollama_service
ensure_ollama_server
install_models
chmod +x "$APP_DIR/iniciar-chat.sh"

case "$(uname -s)" in
  Darwin) install_mac_launcher ;;
  Linux) install_linux_launcher ;;
esac

stop_temporary_ollama

success 'IA Local quedó instalado correctamente.'
if [ "$NO_LAUNCH" -eq 0 ]; then
  step 'Abriendo IA Local'
  if [ "$(uname -s)" = 'Darwin' ]; then open "$HOME/Applications/IA Local.app"
  else nohup "$APP_DIR/iniciar-chat.sh" >"$RUNTIME_DIR/logs/launcher.log" 2>&1 & fi
fi
