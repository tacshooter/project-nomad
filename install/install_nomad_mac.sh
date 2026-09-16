#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# Project NOMAD — macOS Installer (Apple Silicon)
#
# Self-contained: generates secrets, fills in the
# compose file, starts everything. No manual edits.
#
# Usage:  bash install_nomad_mac.sh
# ─────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

header() { echo -e "\n${CYAN}${BOLD}═══ $1 ═══${RESET}\n"; }
ok()     { echo -e "  ${GREEN}✓${RESET} $1"; }
warn()   { echo -e "  ${YELLOW}⚠${RESET} $1"; }
info()   { echo -e "  ${CYAN}→${RESET} $1"; }
fail()   { echo -e "\n  ${RED}✗ $1${RESET}\n"; exit 1; }

# ── Config (override via env) ─────────────────

URL="${URL:-http://localhost:8080}"
NOMAD_DIR="${NOMAD_DIR:-$HOME/project-nomad}"
STORAGE_DIR="${STORAGE_DIR:-$NOMAD_DIR/storage}"
IMAGE_PREFIX="${IMAGE_PREFIX:-ghcr.io/crosstalk-solutions}"
COMPOSE_SRC="${COMPOSE_SRC:-https://raw.githubusercontent.com/Crosstalk-Solutions/project-nomad/main/install/management_compose.yaml}"

# BSD sed on macOS, GNU sed elsewhere (lets this be tested on Linux)
if [[ "$(uname -s)" == "Darwin" ]]; then
    SED_INPLACE=(sed -i '')
else
    SED_INPLACE=(sed -i)
fi

# ── Preflight ─────────────────────────────────

header "Project NOMAD — macOS Installer"
echo -e "${DIM}  Self-contained offline knowledge system${RESET}"
echo -e "${DIM}  for Apple Silicon Macs${RESET}\n"

ARCH="$(uname -m)"
if [[ "$ARCH" != "arm64" && "$ARCH" != "aarch64" ]]; then
    warn "Expected Apple Silicon (arm64), detected: $ARCH"
    if [[ "$(uname -s)" != "Darwin" ]]; then
        fail "This installer is for macOS. For Linux use install_nomad.sh"
    fi
else
    ok "Apple Silicon detected ($ARCH)"
fi

uname -s | grep -q Darwin || fail "This installer is for macOS only"

command -v docker >/dev/null 2>&1 \
    || fail "Docker not found. Install Docker Desktop first:\n      https://www.docker.com/products/docker-desktop/"
ok "Docker $(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"

docker info >/dev/null 2>&1 \
    || fail "Docker is installed but not running. Start Docker Desktop and re-run."
ok "Docker engine is running"

command -v openssl >/dev/null 2>&1 || fail "openssl not found (should ship with macOS)"
command -v curl >/dev/null 2>&1 || fail "curl not found (should ship with macOS)"

# ── Ollama ────────────────────────────────────

OLLAMA_OK=false
OLLAMA_URL="http://host.docker.internal:11434"

header "AI Assistant (Ollama)"

if ! command -v ollama >/dev/null 2>&1; then
    warn "Ollama not found on PATH."
    info "Install with:  brew install ollama"
    info "Or download:   https://ollama.com/download"
    echo ""
    echo -e "  ${DIM}NOMAD can still run without AI — you can add Ollama later.${RESET}"
    read -r -p "  Continue without AI features? [Y/n]: " yn
    [[ "${yn:-Y}" =~ ^[Yy]$ ]] || exit 0
else
    ok "Ollama found"

    # Containers reach the Mac host via host.docker.internal, but Ollama binds
    # to 127.0.0.1 by default — Docker cannot reach that. Bind to all interfaces.
    if [[ "$(launchctl getenv OLLAMA_HOST)" != "0.0.0.0" ]]; then
        info "Binding Ollama to 0.0.0.0 so containers can reach it..."
        launchctl setenv OLLAMA_HOST "0.0.0.0"
        warn "Restart Ollama for the change to take effect (quit it from the menu bar, then reopen)."
    fi

    if curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
        ok "Ollama server is responding"
        OLLAMA_OK=true
    else
        warn "Ollama isn't responding on port 11434."
        info "Start it: open the Ollama app, or run 'ollama serve'"
        OLLAMA_OK=false
    fi

    if [[ "$OLLAMA_OK" == true ]]; then
        echo ""
        echo -e "  ${CYAN}Recommended models for Apple Silicon:${RESET}"
        echo "    1) llama3.2:3b    fast,   ~2GB,  runs on 8GB Macs"
        echo "    2) llama3.1:8b    better, ~5GB,  needs 16GB"
        echo "    3) qwen2.5:7b     coding, ~4.5GB"
        echo "    4) skip — pull later with 'ollama pull <model>'"
        echo ""
        read -r -p "  Pull a model now? [1-4, default 4]: " model_choice
        case "${model_choice:-4}" in
            1) ollama pull llama3.2:3b && ok "llama3.2:3b ready" ;;
            2) ollama pull llama3.1:8b && ok "llama3.1:8b ready" ;;
            3) ollama pull qwen2.5:7b  && ok "qwen2.5:7b ready" ;;
            *) info "Skipped — pull models any time with 'ollama pull <model>'" ;;
        esac
    fi
fi

# ── Secrets ───────────────────────────────────

header "Configuration"

APP_KEY="$(openssl rand -hex 16)"
DB_PASSWORD="$(openssl rand -hex 16)"
MYSQL_ROOT_PASSWORD="$(openssl rand -hex 16)"
ok "Generated random secrets"

LOCAL_IP="$(ipconfig getifaddr en0 2>/dev/null || true)"
[[ -n "$LOCAL_IP" ]] && info "LAN address: http://${LOCAL_IP}:8080"

mkdir -p "$NOMAD_DIR" "$STORAGE_DIR"
ok "Project dir: $NOMAD_DIR"

# ── Fetch compose ─────────────────────────────

info "Downloading compose file..."
curl -fsSL "$COMPOSE_SRC" -o "$NOMAD_DIR/docker-compose.yml" \
    || fail "Could not download the compose file. Check your network and re-run."
ok "Downloaded docker-compose.yml"

# ── Relocate storage (Mac) ────────────────────

# The stock compose hardcodes /opt/project-nomad, which needs sudo on macOS.
# Rewrite it to the user-owned project dir. The updater volume must match the
# compose file's location, so a global rewrite keeps all six references in sync.
"${SED_INPLACE[@]}" "s|/opt/project-nomad|${NOMAD_DIR}|g" "$NOMAD_DIR/docker-compose.yml"
ok "Storage relocated to ${STORAGE_DIR}"

# Optional: point at a different image registry (e.g. a fork with arm64 builds)
if [[ "$IMAGE_PREFIX" != "ghcr.io/crosstalk-solutions" ]]; then
    "${SED_INPLACE[@]}" "s|ghcr.io/crosstalk-solutions|${IMAGE_PREFIX}|g" "$NOMAD_DIR/docker-compose.yml"
    ok "Images sourced from ${IMAGE_PREFIX}"
fi

# ── Fill placeholders ─────────────────────────

# The stock compose uses a bare "replaceme" on 5 lines. Anchor on the key name
# so each gets the right value. MYSQL_PASSWORD must equal DB_PASSWORD (the admin
# service connects to MySQL with it) — both get the same secret.
"${SED_INPLACE[@]}" \
    -e "s|\(APP_KEY=\)replaceme|\1${APP_KEY}|" \
    -e "s|\(URL=\)replaceme|\1${URL}|" \
    -e "s|\(DB_PASSWORD=\)replaceme|\1${DB_PASSWORD}|" \
    -e "s|\(MYSQL_PASSWORD=\)replaceme|\1${DB_PASSWORD}|" \
    -e "s|\(MYSQL_ROOT_PASSWORD=\)replaceme|\1${MYSQL_ROOT_PASSWORD}|" \
    "$NOMAD_DIR/docker-compose.yml"

# Only real assignments count — the stock file's header comment mentions the
# word "replaceme", so a bare grep would falsely abort a good install.
if grep -qE '^[^#]*=replaceme' "$NOMAD_DIR/docker-compose.yml"; then
    warn "Unresolved placeholders remain:"
    grep -nE '^[^#]*=replaceme' "$NOMAD_DIR/docker-compose.yml" | sed 's/^/      /'
    fail "Refusing to start with unresolved placeholders."
fi
ok "All placeholders resolved"

# ── Start ─────────────────────────────────────

header "Starting Project NOMAD"

cd "$NOMAD_DIR"
docker compose up -d || fail "docker compose up failed. See output above."

info "Waiting for MySQL..."
for _ in $(seq 1 45); do
    if docker compose exec -T mysql mysqladmin ping -h localhost --silent >/dev/null 2>&1; then
        ok "MySQL ready"
        break
    fi
    sleep 2
done

info "Waiting for the Command Center..."
ADMIN_UP=false
for _ in $(seq 1 45); do
    code="$(curl -s -o /dev/null -w '%{http_code}' "$URL" 2>/dev/null || echo 000)"
    if [[ "$code" =~ ^(200|302|303)$ ]]; then
        ok "Command Center is up"
        ADMIN_UP=true
        break
    fi
    sleep 2
done

[[ "$ADMIN_UP" == true ]] || warn "Admin panel hasn't responded yet — give it another minute."

# ── Wire up Ollama ────────────────────────────

# NOMAD stores the remote Ollama URL in its own database (KVStore), not in the
# compose environment, so it has to be set through the API after boot.
if [[ "$OLLAMA_OK" == true && "$ADMIN_UP" == true ]]; then
    info "Registering Ollama with NOMAD..."
    resp="$(curl -s -X POST "$URL/api/ollama/configure-remote" \
        -H 'Content-Type: application/json' \
        -d "{\"remoteUrl\":\"${OLLAMA_URL}\"}" 2>/dev/null || true)"
    if echo "$resp" | grep -qiE '"success"|"url"|"remoteUrl"' && ! echo "$resp" | grep -qi '"error"'; then
        ok "Ollama connected → ${OLLAMA_URL}"
    else
        warn "Couldn't auto-register Ollama — set it in the UI (see below)."
    fi
fi

# ── Done ──────────────────────────────────────

header "Installation Complete"

echo -e "  ${GREEN}${BOLD}Project NOMAD is running.${RESET}\n"
echo -e "  Open:      ${CYAN}${URL}${RESET}"
[[ -n "$LOCAL_IP" ]] && echo -e "  On LAN:    ${CYAN}http://${LOCAL_IP}:8080${RESET}"
echo -e "  Directory: ${CYAN}${NOMAD_DIR}${RESET}"
echo -e "  Storage:   ${CYAN}${STORAGE_DIR}${RESET}"
echo ""

if [[ "$OLLAMA_OK" != true ]]; then
    echo -e "  ${YELLOW}AI is not wired up yet.${RESET} To enable it:"
    echo -e "    1. Install/start Ollama:  ${CYAN}brew install ollama${RESET}"
    echo -e "    2. Bind to all interfaces: ${CYAN}launchctl setenv OLLAMA_HOST 0.0.0.0${RESET}"
    echo -e "    3. Restart Ollama, then in NOMAD: ${CYAN}Settings → AI → Remote Ollama${RESET}"
    echo -e "       and enter ${CYAN}${OLLAMA_URL}${RESET}"
    echo ""
fi

echo -e "  Next: open ${CYAN}${URL}${RESET} and finish the Easy Setup wizard"
echo -e "        (accounts, content packs, Wikipedia depth)."
echo ""
echo -e "  ${DIM}Manage:  docker compose ps${RESET}"
echo -e "  ${DIM}Stop:    docker compose down${RESET}"
echo -e "  ${DIM}Logs:    docker compose logs -f${RESET}"
echo -e "  ${DIM}Guide:   docs/INSTALL_MAC.md${RESET}"
echo ""