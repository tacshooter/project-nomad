# Installing Project NOMAD on macOS (Apple Silicon)

Project NOMAD runs on Apple Silicon Macs via Docker Desktop with Ollama running **natively** (not in Docker) for full Metal acceleration.

## Quick Start — One Command

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Crosstalk-Solutions/project-nomad/main/install/install_nomad_mac.sh)
```

The installer handles everything:

- Checks your architecture and Docker Desktop
- Generates all secrets (APP_KEY, database passwords)
- Downloads and configures the compose file
- Relocates storage to `~/project-nomad` (no `sudo` needed)
- Detects Ollama and binds it so containers can reach it
- Starts all containers and waits for readiness
- Registers Ollama with NOMAD automatically

**Prerequisite:** [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed and running. Ollama is optional — the installer will offer to set it up, and NOMAD runs fine without it (you just lose AI features).

### Installer environment overrides

| Variable | Default | Purpose |
|----------|---------|---------|
| `URL` | `http://localhost:8080` | Address you'll access NOMAD at |
| `NOMAD_DIR` | `~/project-nomad` | Where data and compose file live |
| `STORAGE_DIR` | `$NOMAD_DIR/storage` | Where content packs are stored |
| `IMAGE_PREFIX` | `ghcr.io/crosstalk-solutions` | Point at a fork's images |
| `COMPOSE_SRC` | upstream `management_compose.yaml` | Alternate compose source |

Example — accept LAN connections and keep data on an external drive:

```bash
NOMAD_DIR=/Volumes/External/nomad URL=http://192.168.1.50:8080 \
  bash install_nomad_mac.sh
```

---

## Manual Installation

If you'd rather do it by hand, or need to debug the installer:

### 1. Install Ollama (recommended)

```bash
brew install ollama
```

Bind it so Docker containers can reach it — by default Ollama listens on `127.0.0.1`, which containers **cannot** see:

```bash
launchctl setenv OLLAMA_HOST "0.0.0.0"
```

Then restart Ollama (quit it from the menu bar and reopen, or `ollama serve`).

### 2. Set up the project directory

```bash
mkdir -p ~/project-nomad/storage
cd ~/project-nomad
curl -fsSL https://raw.githubusercontent.com/Crosstalk-Solutions/project-nomad/main/install/management_compose.yaml \
  -o docker-compose.yml
```

### 3. Relocate storage paths

The stock compose hardcodes `/opt/project-nomad`, which needs `sudo` on macOS. Rewrite it to your home directory. All six references must move together — in particular the `updater` volume must match wherever the compose file lives, or in-UI updates break:

```bash
sed -i '' "s|/opt/project-nomad|$HOME/project-nomad|g" docker-compose.yml
```

### 4. Fill in the placeholders

The compose file has five `replaceme` values. Each is a bare `replaceme` — anchor on the key name so each gets the right value.

⚠️ `MYSQL_PASSWORD` **must equal** `DB_PASSWORD` — the admin service uses it to connect to MySQL. Generated here as one variable used twice:

```bash
APP_KEY=$(openssl rand -hex 16)          # must be ≥16 chars
DB_PASSWORD=$(openssl rand -hex 16)
MYSQL_ROOT_PASSWORD=$(openssl rand -hex 16)
URL="http://localhost:8080"

sed -i '' \
  -e "s|\(APP_KEY=\)replaceme|\1${APP_KEY}|" \
  -e "s|\(URL=\)replaceme|\1${URL}|" \
  -e "s|\(DB_PASSWORD=\)replaceme|\1${DB_PASSWORD}|" \
  -e "s|\(MYSQL_PASSWORD=\)replaceme|\1${DB_PASSWORD}|" \
  -e "s|\(MYSQL_ROOT_PASSWORD=\)replaceme|\1${MYSQL_ROOT_PASSWORD}|" \
  docker-compose.yml
```

Verify nothing is left — note the file's **header comment** mentions the word "replaceme", so match on assignments only:

```bash
grep -nE '^[^#]*=replaceme' docker-compose.yml   # should print nothing
```

### 5. Start it

```bash
docker compose up -d
docker compose ps
```

Open **http://localhost:8080**.

### 6. Connect Ollama

NOMAD stores the Ollama endpoint in its own database — it is **not** a compose environment variable. Set it in the UI under **Settings → AI → Remote Ollama** with:

```
http://host.docker.internal:11434
```

`host.docker.internal` resolves to your Mac from inside the container. If you set `OLLAMA_HOST` correctly in step 1, the connection test passes.

Pull models with:

```bash
ollama pull llama3.2:3b    # fast, ~2GB, runs on 8GB Macs
ollama pull llama3.1:8b    # better quality, ~5GB, needs 16GB
ollama pull qwen2.5:7b     # strong coding model
```

---

## Why Ollama Runs Outside Docker

Docker on macOS has **no GPU passthrough** — the Linux VM that runs containers can't see the Apple GPU. Ollama inside a container therefore falls back to CPU inference, which is unusably slow.

Running Ollama natively gives it Metal/Metal Performance Shaders acceleration, so responses come back in seconds instead of minutes. NOMAD is designed for this: it supports pointing at an external Ollama server, which is exactly what the steps above do.

Verify acceleration is active:

```bash
ollama ps     # should report 100% GPU
```

---

## Notes for ARM64

NOMAD's custom images (`project-nomad`, `-sidecar-updater`, `-disk-collector`) are built multi-arch (`linux/amd64` + `linux/arm64`). Supporting infrastructure — `mysql:8.0`, `redis:7-alpine`, and `amir20/dozzle` — publishes ARM64 images already.

If you pull an older single-arch tag, Docker Desktop will fall back to Rosetta emulation. It works, but it's slow and CPU-heavy; prefer a multi-arch tag.

---

## Troubleshooting

**`no matching manifest for linux/arm64/v8`**
Older single-arch image. Update to a release with multi-arch builds, or set `IMAGE_PREFIX` to a registry that publishes them.

**Ollama connection test fails in the UI**
Check, in order:
1. `curl http://localhost:11434/api/tags` works on the Mac
2. `launchctl getenv OLLAMA_HOST` prints `0.0.0.0`
3. Ollama was **restarted** after setting it
4. You're using `host.docker.internal:11434`, not `localhost:11434`

**`ERROR: for admin … bind source path does not exist`**
The compose file still points at `/opt/project-nomad`. Re-run step 3.

**admin container restarts in a loop**
Almost always the password mismatch — confirm `MYSQL_PASSWORD` equals `DB_PASSWORD` in `docker-compose.yml`, then `docker compose down && docker compose up -d`.

**Port 8080 already in use**
Change the mapping in the `ports:` section (`"9090:8080"`), update `URL` to match, and `docker compose up -d`.

**Updating from the UI fails**
The `updater` volume must point at the exact directory containing `docker-compose.yml`. If you moved the compose file without re-running step 3, update it to match.
