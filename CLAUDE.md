# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Yushufang** (御书房) is a multi-agent AI collaboration system built on the **[OpenClaw](https://github.com/openclaw/openclaw)** framework, customized for personal academic developers. It maps China's ancient Ming Dynasty governmental structure onto a modern AI agent team — each minister is a specialized AI agent (Discord Bot) with clear domain responsibility. Users issue "imperial decrees" by @mentioning agents in Discord.

- License: MIT | Version: 1.2.0 | Author: Lonin
- Node.js >= 22.16.0 required

## Key Commands

### Installation
```bash
bash scripts/full-install.sh          # Full local install (支持远程 curl)
bash install-mac.sh                   # macOS-specific install
docker compose up -d                  # Docker deployment
```

### Running & Testing
```bash
npm test                              # Run Jest tests
npm run test:coverage                 # Run tests with coverage
npm run lint                          # ShellCheck shell scripts + syntax check JS
npm run health                        # Run health check
```

### Docker
```bash
docker compose up -d                  # Start containers
docker build -t boluobobo/ai-court:latest .   # Build image
```

### Regime Management
```bash
bash scripts/switch-regime.sh <regime>  # Switch between 明朝内阁制/唐朝三省制/现代企业制
bash doctor.sh                          # One-click diagnostic
bash scripts/safe-update.sh             # Safe update with backup
```

### GUI
```bash
cd gui && npm install && npm run build   # Build frontend (React+Vite+TS)
cd gui/server && npm install && node index.js   # Start backend, access http://<host>:18795
```

### Configuration
```bash
bash scripts/health-check.sh          # Health check
bash scripts/memory-backup.sh         # Backup/restore agent memories
bash scripts/cleanup-repo.sh          # Repository cleanup
```

## Architecture

### Three Regimes (制度)

The system supports three organizational configurations, selectable via `scripts/switch-regime.sh`:

| Regime | Config Dir | Agents | Flow |
|---|---|---|---|
| **明朝内阁制** (default) | `configs/ming-neige/` | 18 agents | 司礼监接旨 → 内阁优化 → 六部执行 |
| **唐朝三省制** | `configs/tang-sansheng/` | 14 agents | 中书起草 → 门下审核 → 尚书执行 |
| **现代企业制** | `configs/modern-ceo/` | 14 agents | CEO决策 → Board审议 → CxO执行 |

### Config Structure

Each regime directory (e.g., `configs/ming-neige/`) contains:
- **`openclaw.json`** — Main OpenClaw configuration with all agent definitions, channels, bindings
- **`SOUL.md`** — System-level behavioral rules and communication style for the regime
- **`agents/`** — Individual agent persona files (e.g., `agents/silijian.md`)

The root `openclaw.example.json` is the master template. During installation it's copied to `~/.openclaw/openclaw.json` and the user fills in API keys and Discord bot tokens.

### How OpenClaw Works

The system runs as a single Node.js daemon (`openclaw gateway`) on port **18789**:

1. Each agent has a dedicated Discord Bot account (one token per agent)
2. Messages are routed by @mention matching to the correct agent
3. Independent sessions per user × agent
4. Agents can delegate to each other via `sessions_send`/`sessions_spawn`
5. GitHub webhook triggers automatic code review by 都察院 (via `.github/workflows/duchayuan-review.yml`)

### Model Strategy

- **strong-model**: Complex reasoning/code (司礼监, 内阁, 兵部, 都察院, 翰林院)
- **fast-model**: Simpler tasks (礼部, 工部, 吏部, 刑部, auxiliary agents)

### CI/CD

`.github/workflows/`:
- **`ci.yml`** — JSON validation, ShellCheck, Docker build, server syntax check
- **`docker-build.yml`** — Docker image build/push to `boluobobo/ai-court:latest`
- **`duchayuan-review.yml`** — Automated code review workflow

## Important Directory Map

| Directory | Purpose |
|---|---|
| `configs/` | All configurations: regimes (`ming-neige/`, `tang-sansheng/`, `modern-ceo/`) and Feishu variants (`feishu/`, `feishu-ming/`, `feishu-tang/`, `feishu-modern/`) |
| `skills/` | 18 custom OpenClaw skills (novel-writing, quadrants, self-improving, etc.) |
| `scripts/` | ~37 utility scripts (install, backup, regime switching, health checks) |
| `docs/` | ~60 documentation files (setup, troubleshooting, architecture) |
| `gui/` | React+TypeScript+Vite Web Dashboard (frontend) + Express backend (`gui/server/`) |
| `docker/` | Docker entry/init scripts |
| `tests/` | Jest unit tests (4 test files) |
| `extensions/` | Optional novel-openviking plugin (3D persistent memory for novel writing) |

## Key Files

| Path | What |
|---|---|
| `openclaw.example.json` | Master configuration template with all agent definitions |
| `Dockerfile` | Multi-stage build (GUI builder + main image with OpenClaw + Chromium + OpenViking) |
| `docker-compose.yml` | Production compose with resource limits, volumes, health check |
| `entrypoint.sh` | Container startup: launches OpenClaw Gateway + GUI server |
| `docs/README.md` | Main documentation entry point |
