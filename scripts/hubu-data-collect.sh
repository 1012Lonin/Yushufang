#!/bin/bash
# scripts/hubu-data-collect.sh
# 每 30 分钟由系统 cron 运行，不调用 LLM
# 用途：拉取 API 用量数据 + 阈值检查 + 异常告警

AUTH_TOKEN="${BOLUO_AUTH_TOKEN}"
DATA_DIR="$HOME/clawd-hubu/data"
mkdir -p "$DATA_DIR"

# 1. 拉取最新数据
RESP=$(curl -s "http://localhost:18795/api/tokens" \
  -H "Authorization: Bearer $AUTH_TOKEN")

if [ -z "$RESP" ]; then
  echo "$(date): Empty response" >> "$DATA_DIR/collect.log"
  exit 1
fi
if ! echo "$RESP" | python3 -c "import sys,json;json.load(sys.stdin)" 2>/dev/null; then
  echo "$(date): Invalid JSON response" >> "$DATA_DIR/collect.log"
  exit 1
fi
echo "$RESP" > "$DATA_DIR/api-usage.json"

# 2. 解析当日用量
TOTAL=$(python3 -c "
import json
d = json.load(open('$DATA_DIR/api-usage.json'))
print(d.get('totalTokens', 0))
")

# 3. 阈值配置（可按需调整）
MONTHLY_LIMIT="${HUBU_MONTHLY_LIMIT:-5000000}"
DAILY_SOFT_LIMIT=70000
DAILY_HARD_LIMIT=170000
PROGRESS=$(python3 -c "print(int($TOTAL / $MONTHLY_LIMIT * 100))")

# 4. 实时告警：当日异常
if python3 -c "exit(0 if $TOTAL > $DAILY_HARD_LIMIT else 1)" 2>/dev/null; then
  echo "WARNING $(date): daily $TOTAL exceeds hard limit $DAILY_HARD_LIMIT" >> "$DATA_DIR/alerts.log"
  # 超过 80% 月供 → 立即告警
  if [ "$PROGRESS" -ge 80 ]; then
    openclaw message send --channel discord --account silijian \
      --target "YOUR_CHANNEL_ID" \
      --message "⚠️ **户部紧急告警**: 本月已消耗 ${TOTAL} tokens（${PROGRESS}%），已达月限制 80%！请立即审查高耗能部门。" \
      2>/dev/null || true
  fi
fi

# 5. 记录
echo "$(date): total=$TOTAL tokens, progress=${PROGRESS}% (limit=${MONTHLY_LIMIT})" >> "$DATA_DIR/collect.log"
