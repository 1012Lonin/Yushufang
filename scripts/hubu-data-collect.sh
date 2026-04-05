#!/bin/bash
# scripts/hubu-data-collect.sh
# 每 30 分钟由系统 cron 运行，不调用 LLM
# 所有逻辑在 hubu_data_collect.py 中实现
# 用法: ./hubu-data-collect.sh [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 环境变量（覆盖 Python 默认阈值）
export BOLUO_AUTH_TOKEN="${BOLUO_AUTH_TOKEN:-}"
export HUBU_DATA_DIR="${HUBU_DATA_DIR:-$HOME/clawd-hubu/data}"
export HUBU_GUI_URL="${HUBU_GUI_URL:-http://localhost:18795}"
export HUBU_DISCORD_CHANNEL="${HUBU_DISCORD_CHANNEL:-YOUR_CHANNEL_ID}"
export HUBU_DISCORD_ACCOUNT="${HUBU_DISCORD_ACCOUNT:-silijian}"
export OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"

# 阈值环境变量（可选，不设置则用 Python 默认值）
export HUBU_MONTHLY_LIMIT="${HUBU_MONTHLY_LIMIT:-}"
export HUBU_MONTHLY_SOFT="${HUBU_MONTHLY_SOFT:-}"
export HUBU_MONTHLY_HARD="${HUBU_MONTHLY_HARD:-}"
export HUBU_WEEKLY_SOFT="${HUBU_WEEKLY_SOFT:-}"
export HUBU_WEEKLY_HARD="${HUBU_WEEKLY_HARD:-}"
export HUBU_DAILY_SOFT="${HUBU_DAILY_SOFT:-}"
export HUBU_DAILY_HARD="${HUBU_DAILY_HARD:-}"
export HUBU_ROLLING_WINDOW_HOURS="${HUBU_ROLLING_WINDOW_HOURS:-}"
export HUBU_ROLLING_SOFT="${HUBU_ROLLING_SOFT:-}"
export HUBU_ROLLING_HARD="${HUBU_ROLLING_HARD:-}"
export HUBU_ALERT_COOLDOWN_HOURS="${HUBU_ALERT_COOLDOWN_HOURS:-}"

python3 "$SCRIPT_DIR/hubu_data_collect.py" "$@"
