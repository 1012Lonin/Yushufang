#!/bin/bash
# ============================================
# 御书房 · 更新前检查脚本
#
# 功能：
# 1. 配置完整性（JSON 格式）
# 2. 安全配置检查（allowBots / @everyone / @here）
# 3. 人设完整性
# 4. API Key / Discord Token 配置
# 5. Gateway 状态
# 6. Git 状态（未提交变更 / 落后远程）
# 7. 备份状态
# 8. Git Hook 保护检查与安装
#
# 用法：
#   bash scripts/pre-update-check.sh          # 检查
#   bash scripts/pre-update-check.sh --install-hook  # 安装 git hook
# ============================================

set -uo pipefail  # 注意：不使用 -e，使 ((issues++)) 在 issues=0 时不导致脚本中途退出，确保完成全部 10 项检查

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 颜色（在 set -u 下，fatal 消息需在双安装检查前定义）
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# 配置目录：优先环境变量，否则自动检测 ~/.openclaw 和 ~/.clawdbot，双安装时报错
if [ -n "${CONFIG_DIR:-}" ]; then
  : # operator override，保留原值
elif [ -f "$HOME/.openclaw/openclaw.json" ] && [ -f "$HOME/.clawdbot/openclaw.json" ]; then
  echo -e "${RED}✗ 错误：~/.openclaw 和 ~/.clawdbot 同时存在${NC}" >&2
  echo "  请明确指定：CONFIG_DIR=~/.openclaw 或 CONFIG_DIR=~/.clawdbot bash $0" >&2
  exit 1
elif [ -f "$HOME/.openclaw/openclaw.json" ]; then
  CONFIG_DIR="$HOME/.openclaw"
elif [ -f "$HOME/.clawdbot/openclaw.json" ]; then
  CONFIG_DIR="$HOME/.clawdbot"
else
  CONFIG_DIR=""
fi
CONFIG_FILE="${CONFIG_DIR:+$CONFIG_DIR/openclaw.json}"

# 备份目录：优先环境变量，其次基于检测到的配置目录，最后回退到 ~/.openclaw
BACKUP_DIR="${BACKUP_DIR:-${CONFIG_DIR:+$CONFIG_DIR/backups}}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/.openclaw/backups}"


# jq 辅助函数：查询失败返回空字符串而非崩溃
_jq() {
    jq -r "$1" "$CONFIG_FILE" 2>/dev/null || echo ""
}

# 计数器
issues=0
warnings=0

# ============================================
# 跨平台辅助函数
# ============================================

# 计算两个 YYYYMMDD 日期之间相差天数（macOS BSD + Linux GNU 兼容）
days_between() {
  local date_str="$1"
  local ts1 ts2
  # 检测 date 命令支持哪种语法
  if date -d "20000101" +%s >/dev/null 2>&1; then
    # GNU/Linux: date -d
    ts1=$(date -d "$date_str" +%s 2>/dev/null || echo 0)
    ts2=$(date +%s)
  else
    # macOS BSD: date -j -f
    ts1=$(date -j -f "%Y%m%d" "$date_str" +%s 2>/dev/null || echo 0)
    ts2=$(date +%s)
  fi
  echo $(( (ts2 - ts1) / 86400 ))
}

# ============================================
# Git Hook 安装
# ============================================
install_git_hooks() {
  local hook_dir="$PROJECT_ROOT/.git/hooks"
  local hook_file="$hook_dir/pre-commit"
  local hook_backup="$hook_dir/pre-commit.pre-yushufang.bak"

  echo -e "${CYAN}[Git Hook]${NC} 安装提交保护钩子..."

  # 检查是否已有钩子
  if [ -f "$hook_file" ] && [ -s "$hook_file" ]; then
    # 已存在御书房 hook，跳过
    if grep -q "御书房" "$hook_file" 2>/dev/null; then
      echo -e "  ${GREEN}✓${NC} 御书房 pre-commit hook 已存在，无需重复安装"
      return 0
    fi
    # 已有其他钩子，先备份
    echo -e "  ${YELLOW}⚠${NC} 检测到已有 pre-commit hook，已备份至："
    echo "     $hook_backup"
    cp "$hook_file" "$hook_backup"
  fi

  # 创建 pre-commit hook：禁止提交真实 API Key / Token
  cat > "$hook_file" <<'HOOK'
#!/bin/bash
# ============================================
# 御书房 · pre-commit 保护钩子
# 自动检查：禁止提交真实敏感信息
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

BLOCKED=0

# 检查真实 API Key 模式
if git diff --cached | grep -Ei '"(apiKey|api_key|api-key)"[[:space:]]*:[[:space:]]*"sk-[a-z0-9]{20,}"' -B1 -A1 | grep -v "^--$" | grep -qEi '"(apiKey|api_key|api-key)"'; then
  echo -e "${RED}✗ 禁止提交：检测到真实 API Key！${NC}"
  echo "    请使用占位符：YOUR_LLM_API_KEY"
  BLOCKED=$((BLOCKED + 1))
fi

# 检查真实 Discord Token 模式
if git diff --cached | grep -Ei '"token"[[:space:]]*:[[:space:]]*"[MN][A-Za-z0-9_-]{20,}"' -B1 -A1 | grep -v "^--$" | grep -qEi '"token"'; then
  echo -e "${RED}✗ 禁止提交：检测到真实 Discord Token！${NC}"
  echo "    请使用占位符：YOUR_DISCORD_TOKEN"
  BLOCKED=$((BLOCKED + 1))
fi

# 检查真实 Anthropic Key
if git diff --cached | grep -Ei '"apiKey"[[:space:]]*:[[:space:]]*"sk-ant-[a-z0-9]{20,}"' >/dev/null; then
  echo -e "${RED}✗ 禁止提交：检测到真实 Anthropic API Key！${NC}"
  BLOCKED=$((BLOCKED + 1))
fi

# 检查 .env 文件（禁止提交完整 .env）
for file in $(git diff --cached --name-only | grep -E "^(\.env|env\.|secrets?)" -i); do
  if [ -f "$file" ]; then
    if grep -qiE "(api[_-]?key|token|secret|password|credential)" "$file" 2>/dev/null; then
      echo -e "${RED}✗ 禁止提交：$file 包含敏感信息！${NC}"
      echo "    请使用 .env.example 作为模板"
      BLOCKED=$((BLOCKED + 1))
    fi
  fi
done

if [ "$BLOCKED" -gt 0 ]; then
  echo ""
  echo -e "${RED}提交被阻止，发现 $BLOCKED 个安全问题。${NC}"
  exit 1
fi

echo -e "${GREEN}✓ 敏感信息检查通过${NC}"
exit 0
HOOK

  chmod +x "$hook_file"
  echo -e "  ${GREEN}✓${NC} pre-commit hook 已安装：$hook_file"
  if [ -f "$hook_backup" ]; then
    echo -e "  ${YELLOW}ℹ${NC} 原钩子已备份：$hook_backup"
  fi
  echo "  功能：提交时自动拦截真实 API Key / Token / .env 敏感文件"
}

# ============================================
# 主流程
# ============================================

echo ""
echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║    🔍 御书房 · 更新前安全检查        ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}配置目录:${NC} ${CONFIG_DIR:-未检测到} (${CONFIG_FILE:-N/A})"
echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
echo ""

# --install-hook 参数：安装 git hook 后直接退出（放在 jq 检查前，避免无 jq 环境无法安装）
if [ "${1:-}" = "--install-hook" ]; then
  install_git_hooks
  exit 0
fi

# 前置检查：jq 是否安装（必须依赖，无则直接退出）
if ! command -v jq >/dev/null 2>&1; then
    echo ""
    echo -e "${RED}✗ jq 未安装，无法运行${NC}"
    echo "  macOS: brew install jq"
    echo "  Linux: sudo apt install jq"
    exit 1
fi

# ============================================
# 检查 1: 配置文件完整性
# ============================================
echo -e "${BOLD}[1/8] 配置文件完整性${NC}"

if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
  if jq empty "$CONFIG_FILE" 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} JSON 格式正确"
  else
    echo -e "  ${RED}✗${NC} JSON 格式错误！"
    issues=$((issues + 1))
  fi
else
  echo -e "  ${RED}✗${NC} 配置文件不存在：$CONFIG_FILE"
  issues=$((issues + 1))
fi
echo ""

# ============================================
# 检查 2: 安全配置（allowBots / @everyone / @here）
# ============================================
echo -e "${BOLD}[2/8] 安全配置${NC}"

if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
  # 2a: allowBots 检查
  allow_bots=$(jq -r '.channels.discord.allowBots // "not-set"' "$CONFIG_FILE" 2>/dev/null)
  if [ "$allow_bots" = "true" ]; then
    echo -e "  ${RED}✗ allowBots=true — 危险！会导致机器人循环引用${NC}"
    echo "    正确值应为：mentions 或 false"
    issues=$((issues + 1))
  elif [ "$allow_bots" = "mentions" ] || [ "$allow_bots" = "false" ]; then
    echo -e "  ${GREEN}✓${NC} allowBots=$allow_bots（安全）"
  else
    echo -e "  ${YELLOW}⚠${NC} allowBots=$allow_bots（请确认是否正确）"
    warnings=$((warnings + 1))
  fi

  # 2b: @everyone 检查
  if grep -q '@everyone' "$CONFIG_FILE" 2>/dev/null; then
    echo -e "  ${RED}✗ 发现 @everyone 配置 — 必须移除（核弹开关）${NC}"
    issues=$((issues + 1))
  else
    echo -e "  ${GREEN}✓${NC} 无 @everyone"
  fi

  # 2c: @here 检查
  if grep -q '@here' "$CONFIG_FILE" 2>/dev/null; then
    echo -e "  ${RED}✗ 发现 @here 配置 — 必须移除${NC}"
    issues=$((issues + 1))
  else
    echo -e "  ${GREEN}✓${NC} 无 @here"
  fi
else
  echo -e "  ${YELLOW}⊘${NC} 跳过（配置文件不存在）"
fi
echo ""

# ============================================
# 检查 3: Agent 人设完整性
# ============================================
echo -e "${BOLD}[3/8] Agent 人设完整性${NC}"

if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
  agent_total=$(jq '.agents.list | length' "$CONFIG_FILE" 2>/dev/null || echo 0)
  persona_total=$(jq '[.agents.list[] | select(.identity.theme != null and .identity.theme != "")] | length' "$CONFIG_FILE" 2>/dev/null || echo 0)

  echo "  Agent 总数：$agent_total"
  echo "  已配置人设：$persona_total"

  if [ "$agent_total" -eq "$persona_total" ] && [ "$agent_total" -gt 0 ]; then
    echo -e "  ${GREEN}✓${NC} 所有 Agent 已配置人设"
  elif [ "$agent_total" -eq 0 ]; then
    echo -e "  ${RED}✗${NC} 未检测到任何 Agent"
    issues=$((issues + 1))
  else
    echo -e "  ${RED}✗${NC} 有 $((agent_total - persona_total)) 个 Agent 缺少人设"
    issues=$((issues + 1))
  fi
else
  echo -e "  ${YELLOW}⊘${NC} 跳过"
fi
echo ""

# ============================================
# 检查 4: API Key 配置
# ============================================
echo -e "${BOLD}[4/8] API Key 配置${NC}"

if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
  provider_count=$(jq '.models.providers | keys | length' "$CONFIG_FILE" 2>/dev/null || echo 0)
  has_real_key=$(jq -r '[.models.providers[].apiKey // "" | select(. != "" and . != "YOUR_LLM_API_KEY" and test("^sk-"))] | length' "$CONFIG_FILE" 2>/dev/null || echo 0)

  echo "  配置 Provider 数：$provider_count"
  echo "  有效 API Key 数：$has_real_key"

  if [ "$has_real_key" -gt 0 ]; then
    echo -e "  ${GREEN}✓${NC} 已配置有效 API Key"
  else
    echo -e "  ${YELLOW}⚠${NC} 未检测到有效 API Key"
    warnings=$((warnings + 1))
  fi
else
  echo -e "  ${YELLOW}⊘${NC} 跳过"
fi
echo ""

# ============================================
# 检查 5: Discord Token 配置
# ============================================
echo -e "${BOLD}[5/8] Discord Token 配置${NC}"

if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
  discord_enabled=$(jq -r '.channels.discord.enabled // false' "$CONFIG_FILE" 2>/dev/null)
  account_count=$(jq '.channels.discord.accounts | keys | length' "$CONFIG_FILE" 2>/dev/null || echo 0)
  has_real_token=$(jq -r '[.channels.discord.accounts[].token // "" | select(. != "" and length > 50)] | length' "$CONFIG_FILE" 2>/dev/null || echo 0)

  echo "  Discord 启用：$discord_enabled"
  echo "  Account 数量：$account_count"
  echo "  有效 Token 数：$has_real_token"

  if [ "$discord_enabled" = "true" ] && [ "$has_real_token" -gt 0 ]; then
    echo -e "  ${GREEN}✓${NC} Discord 配置正常"
  elif [ "$discord_enabled" = "true" ]; then
    echo -e "  ${YELLOW}⚠${NC} Discord 已启用但 Token 可能无效"
    warnings=$((warnings + 1))
  else
    echo -e "  ${BLUE}ℹ${NC} Discord 未启用"
  fi
else
  echo -e "  ${YELLOW}⊘${NC} 跳过"
fi
echo ""

# ============================================
# 检查 6: Gateway 状态
# ============================================
echo -e "${BOLD}[6/8] Gateway 状态${NC}"

if command -v openclaw &>/dev/null; then
  if openclaw gateway status 2>&1 | grep -qi "running"; then
    echo -e "  ${GREEN}✓${NC} Gateway 运行中"
  elif openclaw gateway status 2>&1 | grep -qi "stopped"; then
    echo -e "  ${YELLOW}⚠${NC} Gateway 已停止（更新后可重启）"
    warnings=$((warnings + 1))
  else
    echo -e "  ${YELLOW}⚠${NC} 无法确定 Gateway 状态"
    warnings=$((warnings + 1))
  fi
else
  echo -e "  ${YELLOW}⚠${NC} OpenClaw 未安装"
  warnings=$((warnings + 1))
fi
echo ""

# ============================================
# 检查 7: Git 状态
# ============================================
echo -e "${BOLD}[7/8] Git 状态${NC}"

if [ -d "$PROJECT_ROOT/.git" ]; then
  # 检测默认分支
  default_branch=$(git remote show origin 2>/dev/null | grep "HEAD branch" | awk '{print $NF}' || echo "main")

  cd "$PROJECT_ROOT"

  # 7a: 未提交变更
  uncommitted=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  if [ "$uncommitted" -gt 0 ]; then
    echo -e "  ${YELLOW}⚠${NC} 有 $uncommitted 个未提交变更"
    git status --porcelain 2>/dev/null | head -8 | sed 's/^/      /'
    warnings=$((warnings + 1))
  else
    echo -e "  ${GREEN}✓${NC} 工作区干净"
  fi

  # 7b: 落后远程
  behind=$(git rev-list --left-right --count "HEAD...origin/$default_branch" 2>/dev/null | awk '{print $2}' || echo 0)
  if [ "$behind" -gt 0 ]; then
    echo -e "  ${BLUE}ℹ${NC} 落后远程 $behind 个提交（git pull 将带来更新）"
  else
    echo -e "  ${GREEN}✓${NC} 代码已是最新"
  fi

  # 7c: 领先远程（本地有未推送提交）
  ahead=$(git rev-list --left-right --count "HEAD...origin/$default_branch" 2>/dev/null | awk '{print $1}' || echo 0)
  if [ "$ahead" -gt 0 ]; then
    echo -e "  ${BLUE}ℹ${NC} 本地领先远程 $ahead 个未推送提交"
  fi
else
  echo -e "  ${YELLOW}⚠${NC} 非 Git 仓库，无法自动更新"
  warnings=$((warnings + 1))
fi
echo ""

# ============================================
# 检查 8: 备份状态 + Git Hook
# ============================================
echo -e "${BOLD}[8/8] 备份状态 & Git Hook${NC}"

# 8a: 备份状态
if [ -d "$BACKUP_DIR" ]; then
  latest_manifest=$(find "$BACKUP_DIR" -name "backup-manifest.*.json" -type f 2>/dev/null | sort -r | head -1)
  if [ -n "$latest_manifest" ]; then
    backup_ts=$(echo "$latest_manifest" | grep -oE '[0-9]{8}_[0-9]{6}' | head -1)
    backup_date="${backup_ts:0:8}"
    today=$(date +%Y%m%d)

    echo "  最新备份：$backup_date"

    if [ "$backup_date" = "$today" ]; then
      echo -e "  ${GREEN}✓${NC} 今日已备份"
    else
      days_since=$(days_between "$backup_date")
      echo -e "  ${YELLOW}⚠${NC} 上次备份在 ${days_since} 天前，建议先备份"
      warnings=$((warnings + 1))
    fi
  else
    echo -e "  ${YELLOW}⚠${NC} 无备份记录（建议立即备份）"
    warnings=$((warnings + 1))
  fi
else
  echo -e "  ${RED}✗${NC} 备份目录不存在"
  issues=$((issues + 1))
fi

# 8b: Git Hook 检查
hook_file="$PROJECT_ROOT/.git/hooks/pre-commit"
if [ -f "$hook_file" ] && grep -q "御书房" "$hook_file" 2>/dev/null; then
  echo -e "  ${GREEN}✓${NC} Git Hook 已安装"
else
  echo -e "  ${YELLOW}⚠${NC} Git Hook 未安装（运行 --install-hook 安装）"
  echo "    功能：提交时自动拦截真实 API Key / Token"
  warnings=$((warnings + 1))
fi
echo ""

# ============================================
# 汇总与建议
# ============================================
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo ""

if [ "$issues" -gt 0 ]; then
  echo -e "${RED}✗ 发现 $issues 个严重问题，必须先修复！${NC}"
  echo ""
  echo "  1. 修复配置错误：jq empty ~/.openclaw/openclaw.json"
  echo "  2. 运行：bash scripts/init-personas.sh"
  echo "  3. 重新检查：bash scripts/pre-update-check.sh"
  echo ""
  echo -e "  ${YELLOW}在修复前强烈建议先备份：${NC}"
  echo "    bash scripts/backup-all.sh"
  echo ""
  exit 1

elif [ "$warnings" -gt 0 ]; then
  echo -e "${YELLOW}⚠ 发现 $warnings 个警告，可以继续但建议注意${NC}"
  echo ""
  echo "  建议操作（按顺序）："
  echo ""
  echo "  1. 备份（必须）："
  echo "     bash scripts/backup-all.sh"
  echo ""
  echo "  2. 安装 Git Hook（推荐）："
  echo "     bash scripts/pre-update-check.sh --install-hook"
  echo ""
  echo "  3. 更新："
  echo "     git pull"
  echo "     bash scripts/init-personas.sh"
  echo "     openclaw gateway restart"
  echo ""
  echo "  4. 验证："
  echo "     openclaw status"
  echo "     Discord @mention 任一 Agent"
  echo ""
  echo -ne "  是否继续更新？(y/n): "
  read -r confirm
  if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "已取消。"
    exit 0
  fi
  echo ""

else
  echo -e "${GREEN}✓ 所有检查通过，可以安全更新！${NC}"
  echo ""
  echo "  更新步骤："
  echo ""
  echo "  1. bash scripts/backup-all.sh          # 备份（可选）"
  echo "  2. git pull                           # 拉取更新"
  echo "  3. bash scripts/init-personas.sh      # 注入人设"
  echo "  4. openclaw gateway restart            # 重启 Gateway"
  echo "  5. openclaw status                     # 验证状态"
  echo ""
fi

echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo ""
