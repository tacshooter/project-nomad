# Installing Project NOMAD on macOS (Apple Silicon)

Project NOMAD runs on Apple Silicon Macs via Docker Desktop + native Ollama. This guide assumes you're on macOS 14 (Sonoma) or later with an M-series chip.

## What You'll Need

- **Docker Desktop for Mac** (Apple Silicon)
- **Ollama** (native macOS app — uses Metal/MLX for GPU acceleration)
- ~30GB free disk space (more if downloading full Wikipedia + large AI models)

## Step 1: Install Docker Desktop

Download and install from [docker.com](https://www.docker.com/products/docker-desktop/).

After installation, open Docker Desktop and wait for the engine to start (whale icon stops animating).

## Step 2: Install Ollama

```bash
# Via Homebrew (recommended)
brew install ollama

# Or download from ollama.com
```

Ollama runs natively on Apple Silicon with full Metal GPU acceleration — no Docker GPU passthrough needed.

## Step 3: Clone the Repo

```bash
git clone https://github.com/Crosstalk-Solutions/project-nomad.git
cd project-nomad
```

## Step 4: Configure Environment

Copy the management compose file and fill in your values:

```bash
cp install/management_compose.yaml docker-compose.yml
```

Edit `docker-compose.yml` and replace every `replaceme` with a generated value. Generate passwords:

```bash
# Generate random passwords
openssl rand -hex 16  # for APP_KEY
openssl rand -hex 16  # for DB_PASSWORD
openssl rand -hex 16  # for MYSQL_ROOT_PASSWORD
```

Set `URL=http://localhost:8080` (or your Mac's LAN IP for other devices).

## Step 5: Start NOMAD

```bash
docker compose up -d
```

Wait ~30 seconds for MySQL to initialize, then open **http://localhost:8080**.

## Step 6: Configure Ollama

1. In the NOMAD Command Center, go through **Easy Setup**
2. Under **AI Assistant**, choose **"Use external Ollama server"**
3. Enter URL: `http://host.docker.internal:11434`
4. Download your models through the Ollama app:

```bash
# Recommended models for Apple Silicon
ollama pull llama3.2:3b       # Fast, runs on 8GB Macs
ollama pull llama3.1:8b       # Better quality, needs 16GB
ollama pull mistral:7b        # Good balance
ollama pull qwen2.5:7b        # Strong coding model
```

## Step 7: Install Content

Choose your Wikipedia depth, map regions, and content packs in Easy Setup. See the [main install guide](https://www.projectnomad.us/install) for content recommendations.

---

## What's Different vs Linux

| Feature | Linux (x86) | macOS (ARM64) |
|---------|-------------|---------------|
| Ollama GPU | Docker GPU passthrough (NVIDIA) | Native Metal/MLX via macOS app |
| Install | `sudo bash install_nomad.sh` | Manual `docker compose up` |
| NVIDIA toolkit | Installed automatically | N/A (no NVIDIA on Mac) |
| Storage path | `/opt/project-nomad/storage` | `./storage` (relative to compose file) |

## Troubleshooting

**"docker: no matching manifest for linux/arm64"**
→ You're using an old image. Make sure you're pulling from the multi-arch tag (v1.33.0+).

**Ollama connection refused**
→ Make sure Ollama is running: `ollama serve` or open the Ollama app. Verify: `curl http://localhost:11434/api/tags`

**Slow AI responses**
→ Check you're using Ollama natively (not in Docker). Run `ollama ps` — it should show `100% GPU` for Metal acceleration.

**Port 8080 already in use**
→ Edit `docker-compose.yml` and change the port mapping: `"9090:8080"`, then access at `http://localhost:9090`.