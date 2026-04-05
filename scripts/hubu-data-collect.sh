#!/bin/bash
# scripts/hubu-data-collect.sh
# 每 30 分钟由系统 cron 运行，不调用 LLM
# 阈值：5h 滚动窗口 / 日用量 / 周配额 / 月配额，多层级告警
# 用法: ./hubu-data-collect.sh [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${HUBU_DATA_DIR:-$HOME/clawd-hubu/data}"
STATE_DIR="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
GUI_URL="${HUBU_GUI_URL:-http://localhost:18795}"
DISCORD_CHANNEL="${HUBU_DISCORD_CHANNEL:-YOUR_CHANNEL_ID}"
DISCORD_ACCOUNT="${HUBU_DISCORD_ACCOUNT:-silijian}"

# ─── 默认阈值（统统可被环境变量覆盖）─────────────────────────────
MONTHLY_LIMIT="${HUBU_MONTHLY_LIMIT:-5000000}"
MONTHLY_SOFT="${HUBU_MONTHLY_SOFT:-3500000}"
MONTHLY_HARD="${HUBU_MONTHLY_HARD:-4500000}"
WEEKLY_SOFT="${HUBU_WEEKLY_SOFT:-800000}"
WEEKLY_HARD="${HUBU_WEEKLY_HARD:-1000000}"
DAILY_SOFT="${HUBU_DAILY_SOFT:-120000}"
DAILY_HARD="${HUBU_DAILY_HARD:-166667}"
ROLLING_HOURS="${HUBU_ROLLING_HOURS:-5}"
ROLLING_SOFT="${HUBU_ROLLING_SOFT:-80000}"
ROLLING_HARD="${HUBU_ROLLING_HARD:-120000}"
COOLDOWN_HOURS="${HUBU_COOLDOWN_HOURS:-4}"

DRY_RUN=""
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
fi

# ─── 目录准备 ──────────────────────────────────────────────────
mkdir -p "$DATA_DIR"/{ticks,daily-snapshots,weekly-snapshots,rolling,alerts}

log() {
  echo "$(date '+%Y-%m-%dT%H:%M:%S%z') $*" >> "$DATA_DIR/collect.log"
}

# ─── 获取总量 ──────────────────────────────────────────────────
FETCH_OK=0
fetch_total() {
  local token
  token=$(curl -s "$GUI_URL/api/tokens" \
    -H "Authorization: Bearer ${BOLUO_AUTH_TOKEN:-}" \
    | python3 -c 'import sys,json; print(json.load(sys.stdin).get("totalTokens",-1))' 2>/dev/null)
  if [[ -z "$token" || ! "$token" =~ ^-?[0-9]+$ ]]; then
    FETCH_OK=0
    echo "0"
    return 1
  fi
  FETCH_OK=1
  echo "$token"
}

# ─── 冷却检查 ──────────────────────────────────────────────────
in_cooldown() {
  local key="$1"
  local cooldown_file="$DATA_DIR/alerts/cooldown.json"
  if [[ ! -f "$cooldown_file" ]]; then return 1; fi
  local last
  last=$(python3 -c "import json,sys; d=json.load(open('$cooldown_file')); print(d.get('$key',''))" 2>/dev/null || echo "")
  [[ -z "$last" ]] && return 1
  local last_ts now_ts
  last_ts=$(python3 -c "from datetime import datetime; print(int(datetime.fromisoformat('${last}').timestamp()))")
  now_ts=$(date '+%s')
  local diff=$((now_ts - last_ts))
  [[ $diff -lt $((COOLDOWN_HOURS * 3600)) ]]
}

record_alert() {
  local key="$1"
  local cooldown_file="$DATA_DIR/alerts/cooldown.json"
  python3 -c "
import json, datetime
d = {}
try:
    with open('$cooldown_file') as f: d = json.load(f)
except: pass
d['$key'] = datetime.datetime.now().isoformat()
with open('$cooldown_file', 'w') as f: json.dump(d, f)
" 2>/dev/null || true
}

# ─── 发送 Discord 告警 ────────────────────────────────────────
send_alert() {
  local msg="$1"
  [[ -n "$DRY_RUN" ]] && echo "[DRY-RUN] alert: $msg" && return 0
  openclaw message send \
    --channel discord \
    --account "$DISCORD_ACCOUNT" \
    --target "$DISCORD_CHANNEL" \
    --message "$msg" 2>/dev/null || log "WARNING: failed to send Discord alert"
}

# ─── ISO 周编号 ───────────────────────────────────────────────
iso_week() {
  python3 -c "from datetime import datetime; d=datetime.now(); print(f'{d.isocalendar()[0]}-W{d.isocalendar()[1]:02d}')"
}

# ─── 计算滚动窗口 ─────────────────────────────────────────────
# 从今日 tick 文件读取最近 ROLLING_HOURS 内的记录
# 窗口用量 = 最新 totalTokens - ROLLING_HOURS 前的 totalTokens
rolling_tokens() {
  local tick_file="$DATA_DIR/ticks/$(date '+%Y-%m-%d').jsonl"
  [[ ! -f "$tick_file" ]] && echo "" && return
  local now_ts cutoff_ts
  now_ts=$(date '+%s')
  cutoff_ts=$((now_ts - ROLLING_HOURS * 3600))
  # 找窗口内第一条和最后一条
  python3 -c "
import sys, json, datetime

tick_file = '$tick_file'
cutoff_ts = $cutoff_ts
entries = []
for line in open(tick_file):
    try:
        r = json.loads(line)
        ts = datetime.datetime.fromisoformat(r['ts']).timestamp()
        if ts >= cutoff_ts:
            entries.append((ts, r.get('totalTokens', 0)))
    except: pass

if len(entries) < 2:
    print('')
else:
    entries.sort()
    print(entries[-1][1] - entries[0][1])
" 2>/dev/null || echo ""
}

# ─── 日增量 ──────────────────────────────────────────────────
daily_delta() {
  local prev_day
  prev_day=$(python3 -c "from datetime import date, timedelta; print((date.today()-timedelta(days=1)).isoformat())")
  local prev_file="$DATA_DIR/daily-snapshots/${prev_day}.json"
  local prev_total=0
  if [[ -f "$prev_file" ]]; then
    prev_total=$(python3 -c "import json; print(json.load(open('$prev_file')).get('totalTokens',0))" 2>/dev/null || echo 0)
  fi
  local total_tokens="$1"
  echo $((total_tokens - prev_total))
}

# ─── 周增量 ──────────────────────────────────────────────────
week_total() {
  local wk_file="$DATA_DIR/weekly-snapshots/$(iso_week).json"
  if [[ -f "$wk_file" ]]; then
    python3 -c "import json; print(json.load(open('$wk_file')).get('totalTokens',0))" 2>/dev/null || echo 0
  else
    echo 0
  fi
}

# ─── 评估阈值并告警 ────────────────────────────────────────────
check_thresholds() {
  local rolling="$1"   # 可能为空
  local daily="$2"
  local weekly="$3"
  local monthly="$4"  # 即 totalTokens
  local progress="$5"

  # 5h 滚动窗口
  if [[ -n "$rolling" && "$rolling" -gt 0 ]]; then
    if [[ "$rolling" -gt "$ROLLING_HARD" ]] && ! in_cooldown "ROLLING_HARD"; then
      send_alert ":rotating_light: **户部紧急 — 5小时滚动窗口超限**

当前窗口: ${rolling} / ${ROLLING_HARD} tokens
建议立即审查最近 5 小时内的 API 调用任务。"
      record_alert "ROLLING_HARD"
    elif [[ "$rolling" -gt "$ROLLING_SOFT" ]] && ! in_cooldown "ROLLING_SOFT"; then
      log "ROLLING_SOFT:${rolling}"
      record_alert "ROLLING_SOFT"
    fi
  fi

  # 日用量
  if [[ "$daily" -gt "$DAILY_HARD" ]] && ! in_cooldown "DAILY_HARD"; then
    send_alert ":warning: **户部告警 — 日用量超限**

今日累计: ${daily} / ${DAILY_HARD} tokens
建议 @司礼监 审查今日任务。"
    record_alert "DAILY_HARD"
  elif [[ "$daily" -gt "$DAILY_SOFT" ]] && ! in_cooldown "DAILY_SOFT"; then
    log "DAILY_SOFT:${daily}"
    record_alert "DAILY_SOFT"
  fi

  # 周配额
  if [[ "$weekly" -gt "$WEEKLY_HARD" ]] && ! in_cooldown "WEEKLY_HARD"; then
    send_alert ":chart_with_downwards_trend: **户部告警 — 本周配额超限**

本周累计: ${weekly} / ${WEEKLY_HARD} tokens
建议审阅本周用量构成。"
    record_alert "WEEKLY_HARD"
  elif [[ "$weekly" -gt "$WEEKLY_SOFT" ]] && ! in_cooldown "WEEKLY_SOFT"; then
    log "WEEKLY_SOFT:${weekly}"
    record_alert "WEEKLY_SOFT"
  fi

  # 月配额
  if [[ "$monthly" -gt "$MONTHLY_HARD" ]] && ! in_cooldown "MONTHLY_HARD"; then
    local remaining=$((MONTHLY_LIMIT - monthly))
    local day_of_month
    day_of_month=$(date '+%d')
    local days_left=$((30 - day_of_month + 1))
    local daily_allow=$((remaining / days_left))
    send_alert ":fire: **户部紧急 — 本月配额已达 90%！**

本月累计: ${monthly} / ${MONTHLY_LIMIT} tokens (${progress}%)
剩余: ${remaining} tokens | 剩余天数: ${days_left} | 日均可用: ${daily_allow}
建议 @司礼监 立即节制用量或追加预算！"
    record_alert "MONTHLY_HARD"
  elif [[ "$monthly" -gt "$MONTHLY_SOFT" ]] && ! in_cooldown "MONTHLY_SOFT"; then
    log "MONTHLY_SOFT:${progress}%"
    record_alert "MONTHLY_SOFT"
  fi
}

# ─── 主程序 ──────────────────────────────────────────────────
main() {
  local total_tokens
  total_tokens=$(fetch_total)

  if [[ "$FETCH_OK" -eq 0 ]]; then
    log "ERROR: failed to fetch total tokens from GUI"
    echo "[hubu] ERROR: failed to fetch total tokens from $GUI_URL"
    return 1
  fi

  local progress
  progress=$(python3 -c "print(round(${total_tokens} / ${MONTHLY_LIMIT} * 100, 1))")

  # 滚动窗口
  local rolling
  rolling=$(rolling_tokens)

  # 日增量
  local daily_delta_val
  daily_delta_val=$(daily_delta "$total_tokens")

  # 周增量
  local weekly_val
  weekly_val=$(week_total)

  # ── 写 api-usage.json（向后兼容）─────────────────────────────
  python3 -c "
import json
d = {
  'totalTokens': ${total_tokens},
  'monthlyProgress': ${progress},
  'dailyTokens': ${daily_delta_val},
  'weekNumber': '$(iso_week)',
  'weekTokens': ${weekly_val},
  'rollingWindowTokens': ${rolling:-null},
  'ts': '$(date '+%Y-%m-%dT%H:%M:%S%z')'
}
with open('$DATA_DIR/api-usage.json', 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
"

  # ── 追加 tick ───────────────────────────────────────────────
  echo '{"ts":"'"$(date '+%Y-%m-%dT%H:%M:%S%z')"'","totalTokens":'"$total_tokens"','"'"'dailyTokens'"'"':'"$daily_delta_val"',"monthlyProgress":'"$progress"',"rollingWindowTokens":'"${rolling:-null}"'}' >> "$DATA_DIR/ticks/$(date '+%Y-%m-%d').jsonl"

  # ── 写滚动窗口快照 ──────────────────────────────────────────
  if [[ -n "$rolling" ]]; then
    python3 -c "
import json
with open('$DATA_DIR/rolling/rolling-window.json','w') as f:
    json.dump({'windowTokens':${rolling},'windowHours':${ROLLING_HOURS},'computedAt':'$(date '+%Y-%m-%dT%H:%M:%S%z')'}, f, indent=2, ensure_ascii=False)
"
  fi

  # ── 每日 0 点：写当日快照 ─────────────────────────────────
  local today_snap="$DATA_DIR/daily-snapshots/$(date '+%Y-%m-%d').json"
  if [[ ! -f "$today_snap" ]]; then
    python3 -c "
import json
d = {
  'date': '$(date '+%Y-%m-%d')',
  'totalTokens': ${total_tokens},
  'dailyTokens': ${daily_delta_val},
  'monthlyProgress': ${progress},
  'weekNumber': '$(iso_week)',
  'weekTokens': ${weekly_val},
  'rollingWindowTokens': ${rolling:-null}
}
with open('$today_snap', 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
"
  fi

  # ── 周一 0 点：写周快照 ───────────────────────────────────
  local week_file="$DATA_DIR/weekly-snapshots/$(iso_week).json"
  if [[ ! -f "$week_file" ]]; then
    # 取过去 7 天每日快照
    local daily_files
    daily_files=$(ls -t "$DATA_DIR/daily-snapshots/"*.json 2>/dev/null | head -7)
    python3 -c "
import os, json
files = '''$daily_files'''.strip().split()
daily = []
for f in (files or []):
    try:
        daily.append(json.load(open(f)).get('dailyTokens', 0))
    except: pass
avg = round(sum(daily)/len(daily)) if daily else 0
with open('$week_file', 'w') as f:
    json.dump({'week':'$(iso_week)','totalTokens':${total_tokens},'dailyAvg':avg,'dailyTokens':daily,'monthlyProgress':${progress}}, f, indent=2, ensure_ascii=False)
"
  fi

  # ── 阈值检查 ──────────────────────────────────────────────
  if [[ -z "$DRY_RUN" ]]; then
    check_thresholds "${rolling:-}" "$daily_delta_val" "$weekly_val" "$total_tokens" "$progress"
  fi

  # ── 日志 ──────────────────────────────────────────────────
  log "total=${total_tokens} rolling=${rolling:-null} daily=${daily_delta_val} weekly=${weekly_val} month=${progress}%"
  echo "[hubu] total=${total_tokens} rolling=${rolling:-null} daily=${daily_delta_val} weekly=${weekly_val} month=${progress}%"
}

main
