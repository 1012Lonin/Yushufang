#!/usr/bin/env bash
# ============================================
# 御书房 · 交互式安装配置脚本
#
# 依赖：bash 4+ 或 zsh、jq、openclaw
# 用法：
#   bash scripts/interactive-install.sh
#   zsh scripts/interactive-install.sh
# ============================================

set -euo pipefail

# ============================================
# 颜色常量
# ============================================
CYAN=$'\033[0;36m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[0;31m'
BLUE=$'\033[0;34m'
BOLD=$'\033[1m'
NC=$'\033[0m'

# ============================================
# 脚本路径
# ============================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CFG_FILE="$SCRIPT_DIR/interactive-install.cfg"

# ============================================
# 工具函数
# ============================================

pause() {
  echo ""
  read -p "按 Enter 继续..." </dev/tty
}

confirm() {
  local msg="${1:-确认？}"
  local reply
  read -p "$msg (y/n): " reply </dev/tty
  [[ "$reply" == "y" || "$reply" == "Y" ]]
}

banner() {
  echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║   $1${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
}

info()    { echo -e "  ${CYAN}i${NC} $*"; }
ok()      { echo -e "  ${GREEN}✓${NC} $*"; }
warn()    { echo -e "  ${YELLOW}⚠${NC} $*"; }
fail()    { echo -e "  ${RED}✗${NC} $*" >&2; }

# 跨平台清屏（TERM=dumb 时 clear 不可用）
_clear() { clear 2>/dev/null || printf '\n\n\n\n\n\n\n\n\n\n'; }

# ============================================
# CONFIG_DIR 检测（双安装冲突）
# ============================================
detect_config_dir() {
  if [ -n "${CONFIG_DIR:-}" ]; then
    info "使用 CONFIG_DIR: $CONFIG_DIR"
    return 0
  fi

  local clawd="$HOME/.clawdbot/openclaw.json"
  local openclaw="$HOME/.openclaw/openclaw.json"

  if [ -f "$clawd" ] && [ -f "$openclaw" ]; then
    fail "错误：~/.openclaw 和 ~/.clawdbot 同时存在"
    echo "  请明确指定：CONFIG_DIR=~/.openclaw 或 CONFIG_DIR=~/.clawdbot bash $0"
    exit 1
  elif [ -f "$clawd" ]; then
    CONFIG_DIR="$HOME/.clawdbot"
  elif [ -f "$openclaw" ]; then
    CONFIG_DIR="$HOME/.openclaw"
  else
    CONFIG_DIR="$HOME/.openclaw"
  fi
  info "检测到配置目录：$CONFIG_DIR"
  CONFIG_FILE="$CONFIG_DIR/openclaw.json"
}

# ============================================
# 状态持久化（interactive-install.cfg）
# ============================================
state_save() {
  local var_name="$1"; shift
  local value="$*"

  if [ -f "$CFG_FILE" ]; then
    # 已有变量则更新
    if grep -q "^${var_name}=" "$CFG_FILE" 2>/dev/null; then
      sed -i.bak "s|^${var_name}=.*|${var_name}=\"${value}\"|" "$CFG_FILE"
    else
      echo "${var_name}=\"${value}\"" >> "$CFG_FILE"
    fi
  else
    echo "#!/bin/bash" > "$CFG_FILE"
    echo "# 御书房交互式安装配置 — 由 interactive-install.sh 生成" >> "$CFG_FILE"
    echo "" >> "$CFG_FILE"
    echo "${var_name}=\"${value}\"" >> "$CFG_FILE"
  fi
}

state_load() {
  local var_name="$1"
  if [ -f "$CFG_FILE" ]; then
    grep "^${var_name}=" "$CFG_FILE" 2>/dev/null | sed 's/^[^=]*=//' | tr -d '"'
  fi
}

# ============================================
# 部门定义（编号 1~15）
# ============================================
# 格式：dept_ID="agentId1,agentId2|部门显示名|功能说明"
declare -A DEPT_DEFS
DEPT_DEFS[1]="silijian,neige|核心中枢|任务分发 + Prompt 优化（建议强模型）"
DEPT_DEFS[2]="libu2|吏部|项目管理、知识库维护"
DEPT_DEFS[3]="hubu|户部|API 用量监控、计费报表"
DEPT_DEFS[4]="bingbu|兵部|软件开发、系统架构"
DEPT_DEFS[5]="libu|礼部|品牌营销、社交媒体"
DEPT_DEFS[6]="xingbu|刑部|法务合规、合同审查"
DEPT_DEFS[7]="gongbu|工部|DevOps、服务器运维、健康巡检"
DEPT_DEFS[8]="duchayuan|都察院|独立代码审查、安全审计"
DEPT_DEFS[9]="dianbosi|典簿司|记忆管理、知识归档"
DEPT_DEFS[10]="hanlin_zhang,hanlin_xiuzhuan,hanlin_bianxiu,hanlin_jiantao,hanlin_shujishi|翰林院|论文/小说创作流水线（5 agents）"
DEPT_DEFS[11]="qijuzhu|起居注|日志记录、每日事件记录"
DEPT_DEFS[12]="guozijian|国子监|教育培训、学习计划推送"
DEPT_DEFS[13]="taiyiyuan|太医院|健康管理、训练计划"
DEPT_DEFS[14]="neiwufu|内务府|日常起居、日程管理"
DEPT_DEFS[15]="yushanfang|御膳房|膳食安排、菜谱研究"

# 预设
PRESET_1_DEPT="1,2,3,4,5,6,7,8,9,10,11,12,13,14,15"  # 完整内阁制
PRESET_2_DEPT="1,3,4,7,8,10"                           # 精简版
PRESET_3_DEPT=""                                        # 自定义（空=未选）

# 从部门编号列表获取所有 agent ID
dept_to_agents() {
  local depts="$1"
  local result=""
  for d in $(echo "$depts" | tr ',' ' '); do
    local def="${DEPT_DEFS[$d]}"
    local agents="${def%%|*}"
    [ -n "$result" ] && result="$result,"
    result="${result}${agents}"
  done
  echo "$result"
}

# 获取 agent 总数
count_agents() {
  local agents="$1"
  echo "$(echo "$agents" | tr ',' '\n' | grep -c .)"
}

# ============================================
# 供应商预设
# ============================================
# Provider presets: id|name|baseUrl|apiFormat|modelId|modelName
declare -A PROVIDER_PRESETS
PROVIDER_PRESETS[1]="anthropic|Anthropic|https://api.anthropic.com|anthropic-messages|claude-sonnet-4-6|Claude Sonnet 4.6"
PROVIDER_PRESETS[2]="openai|OpenAI|https://api.openai.com/v1|openai|gpt-4o|GPT-4o"
PROVIDER_PRESETS[3]="deepseek|DeepSeek|https://api.deepseek.com/v1|openai|deepseek-chat|DeepSeek V3"
PROVIDER_PRESETS[4]="openrouter|OpenRouter|https://openrouter.ai/api/v1|openai|anthropic/claude-sonnet-4-6|OpenRouter(多模型聚合)"
PROVIDER_PRESETS[5]="ollama|Ollama|http://localhost:11434/v1|openai|qwen2.5|Qwen2.5(本地)"

# API Format 自动检测（根据 URL）
detect_api_format() {
  local url="$1"
  if echo "$url" | grep -qi "anthropic"; then
    echo "anthropic-messages"
  else
    echo "openai"
  fi
}

# ============================================
# OpenRouter 模型列表（常用）
# ============================================
OPENROUTER_MODELS=(
  "anthropic/claude-sonnet-4-6:Claude Sonnet 4.6"
  "anthropic/claude-opus-4-5:Claude Opus 4.5"
  "openai/gpt-4o:GPT-4o"
  "openai/gpt-4o-mini:GPT-4o Mini"
  "google/gemini-2.5-pro-preview:Gemini 2.5 Pro"
  "deepseek/deepseek-chat-v3:DeepSeek V3"
)

# ============================================
# 通用模型列表（分 Agent 配置时使用）
# ============================================
AGENT_MODEL_OPTIONS=(
  "1:anthropic/claude-sonnet-4-6:Anthropic claude-sonnet-4-6"
  "2:openai/gpt-4o:OpenAI gpt-4o"
  "3:deepseek/deepseek-chat:DeepSeek deepseek-chat"
  "4:openai/gpt-4o-mini:OpenAI gpt-4o-mini（快速）"
  "5:anthropic/claude-haiku-4-5:Anthropic claude-haiku-4-5（轻量）"
)

# ============================================
# 全局状态（本次运行）
# ============================================
SELECTED_DEPT=""           # 逗号分隔的部门编号
SELECTED_AGENTS=""         # 逗号分隔的 agent ID
MODEL_MODE=""              # unified | per-agent
GLOBAL_PROVIDER=""         # 统一模式 provider id
GLOBAL_API_URL=""          # 统一模式 URL
GLOBAL_API_KEY=""          # 统一模式 API Key
GLOBAL_API_FORMAT=""       # 统一模式 apiFormat
GLOBAL_MODEL_ID=""         # 统一模式 model id
declare -A AGENT_MODEL_MAP # 分 Agent 模式：agentId -> provider/modelId

# ============================================
# 主菜单
# ============================================
main_menu() {
  _clear
  echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║    🏯 御书房 · 交互式安装配置        ║${NC}"
  echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
  echo ""
  echo "  0) 退出"
  echo "  1) 安装"
  echo "  2) 配置"
  echo ""

  read -p "请选择 [0/1/2]: " choice </dev/tty
  case "$choice" in
    0) echo "再见！"; exit 0 ;;
    1) install_flow ;;
    2) config_flow ;;
    *) warn "无效选择，请重试。"; pause; main_menu ;;
  esac
}

# ============================================
# 安装流程
# ============================================
install_flow() {
  banner "安装流程"
  echo ""
  info "此流程将引导您完成："
  echo "  ① 选择安装的部门"
  echo "  ② 配置 AI 模型"
  echo "  ③ 执行安装"
  echo ""
  pause

  # ---- 步骤1：选择部门 ----
  dept_select

  # ---- 步骤2：模型配置 ----
  model_mode

  # ---- 步骤3：执行安装 ----
  do_install

  echo ""
  ok "安装完成！"
  echo ""
  echo "  下一步："
  echo "    1. 启动 Gateway：openclaw gateway start"
  echo "    2. 配置 Discord Token：运行本脚本 → 选择 2 配置"
  echo "    3. 查看状态：openclaw status"
  echo ""
  pause
  main_menu
}

# ============================================
# 步骤1：选择部门
# ============================================
dept_select() {
  banner "① 选择部门"

  echo "请选择安装预设："
  echo ""
  echo "  1) 预设1 — 完整内阁制（15 部门，20 agents）"
  echo "  2) 预设2 — 精简版（核心中枢/户部/兵部/工部/都察院/翰林院）"
  echo "  3) 预设3 — 自定义（自行勾选部门）"
  echo ""

  read -p "请选择 [1/2/3]: " preset </dev/tty
  case "$preset" in
    1) SELECTED_DEPT="$PRESET_1_DEPT"; ok "已选择完整内阁制" ;;
    2) SELECTED_DEPT="$PRESET_2_DEPT"; ok "已选择精简版" ;;
    3) SELECTED_DEPT=$(dept_custom_pick); ok "已选择自定义部门" ;;
    *) warn "无效选择"; dept_select; return ;;
  esac

  SELECTED_AGENTS=$(dept_to_agents "$SELECTED_DEPT")
  echo ""
  info "已选部门：$SELECTED_DEPT"
  info "涉及 Agent：$(count_agents "$SELECTED_AGENTS") 个"
  echo ""

  local reply
  read -p "确认部门选择？(y/n): " reply </dev/tty
  if [[ "$reply" != "y" && "$reply" != "Y" ]]; then
    warn "重新选择部门..."
    SELECTED_DEPT=""
    SELECTED_AGENTS=""
    dept_select
  fi
}

# 自定义部门选择
dept_custom_pick() {
  local result=""
  local running=true

  while $running; do
    # 每次循环清屏
    _clear

    echo ""
    echo -e "  ${CYAN}┌──────────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${CYAN}│${NC}  自定义部门选择${NC}                                          ${CYAN}│${NC}"
    echo -e "  ${CYAN}│${NC}  已选: ${result:-无}                                          ${CYAN}│${NC}"
    echo -e "  ${CYAN}└──────────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BOLD}  编号   部门名称          Agent数  功能说明${NC}"
    echo -e "  ${BOLD}  ─────────────────────────────────────────────────────${NC}"

    # 显示所有部门
    for id in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
      local def="${DEPT_DEFS[$id]}"
      local agents="${def%%|*}"
      local name="${def%|*}" && name="${name#*|}"
      local desc="${def##*|}"
      local agent_count
      agent_count=$(echo "$agents" | tr ',' '\n' | grep -c .)
      local marker=""
      # 检查是否已选
      if echo ",$result," | grep -q ",$id,"; then
        marker="${GREEN}[已选]${NC} "
      fi
      printf "  %2s) %b%-12s${NC} %-18s %s\n" "$id" "$marker" "$name" "($agent_count agent)" "$desc"
    done

    echo ""
    echo -e "  ${CYAN}  0) 完成选择${NC}"
    echo ""

    read -p "  输入编号（空格分隔，可多次输入，回车确认）: " input </dev/tty
    case "$input" in
      0) running=false ;;
      *)
        for item in $input; do
          if [[ "$item" =~ ^[0-9]+$ ]] && [ "$item" -ge 1 ] && [ "$item" -le 15 ]; then
            if ! echo ",$result," | grep -q ",$item,"; then
              [ -n "$result" ] && result="$result,"
              result="${result}${item}"
            fi
          fi
        done
        ;;
    esac
  done

  echo "$result"
}

# ============================================
# 步骤2：模型配置
# ============================================
model_mode() {
  banner "② 模型配置"
  echo ""
  echo "  1) 统一（全部 Agent 使用同一模型）"
  echo "  2) 分 Agent 配置（每个 Agent 可单独选择模型）"
  echo ""

  read -p "请选择 [1/2]: " choice </dev/tty
  case "$choice" in
    1) MODEL_MODE="unified";   model_config_unified ;;
    2) MODEL_MODE="per-agent";  model_config_per_agent ;;
    *) warn "无效选择"; model_mode; return ;;
  esac
}

# ---- 统一模型配置 ----
model_config_unified() {
  echo ""
  echo "  请选择模型供应商（按 Enter 使用括号中的默认值）："
  echo ""
  echo "   1) Anthropic  https://api.anthropic.com         claude-sonnet-4-6"
  echo "   2) OpenAI    https://api.openai.com/v1         gpt-4o"
  echo "   3) DeepSeek  https://api.deepseek.com/v1      deepseek-chat"
  echo "   4) OpenRouter https://openrouter.ai/api/v1     多模型聚合"
  echo "   5) Ollama    http://localhost:11434/v1         本地模型"
  echo "   6) 自定义（自行填入所有参数）"
  echo "   7) 跳过（稍后手动配置）"
  echo ""

  read -p "请选择 [1-7]: " choice </dev/tty

  case "$choice" in
    1|2|3|4|5)
      local preset="${PROVIDER_PRESETS[$choice]}"
      GLOBAL_PROVIDER="${preset%%|*}"
      local rest="${preset#*|}"
      GLOBAL_API_URL="${rest%%|*}"
      rest="${rest#*|}"
      GLOBAL_API_FORMAT="${rest%%|*}"
      rest="${rest#*|}"
      GLOBAL_MODEL_ID="${rest%%|*}"
      ;;
    6) model_custom_input ;;
    7) info "跳过模型配置（稍后手动填写）"; return ;;
    *) warn "无效选择"; model_config_unified; return ;;
  esac

  echo ""
  ok "已选择：$GLOBAL_PROVIDER / $GLOBAL_MODEL_ID"
  echo ""
  read -s -p "请输入 API Key（输入时不可见）: " GLOBAL_API_KEY </dev/tty
  echo ""
  if [ -z "$GLOBAL_API_KEY" ]; then
    warn "API Key 为空，跳过（稍后手动填写）"
  else
    ok "API Key 已记录"
  fi
}

# ---- 自定义模型输入 ----
model_custom_input() {
  echo ""
  read -p "  Provider 名称（如 my-provider）: " GLOBAL_PROVIDER </dev/tty
  read -p "  Base URL（如 https://api.example.com/v1）: " GLOBAL_API_URL </dev/tty
  read -p "  Model ID（如 gpt-4o）: " GLOBAL_MODEL_ID </dev/tty
  GLOBAL_API_FORMAT=$(detect_api_format "$GLOBAL_API_URL")
  ok "API Format 自动检测为：$GLOBAL_API_FORMAT"
}

# ---- 分 Agent 配置 ----
model_config_per_agent() {
  echo ""
  info "分 Agent 模型配置模式"
  echo "  您可以选择先设置一个全局默认值，再为特定 Agent 单独覆盖。"
  echo ""

  # 先问全局默认值（可跳过）
  echo "  先设置全局默认模型（所有 Agent 初始使用）："
  echo "   1) Anthropic  claude-sonnet-4-6"
  echo "   2) OpenAI    gpt-4o"
  echo "   3) DeepSeek  deepseek-chat"
  echo "   4) 稍后逐个配置（全部跳过）"
  echo ""

  read -p "请选择 [1-4]: " choice </dev/tty
  case "$choice" in
    1)
      GLOBAL_PROVIDER="anthropic"; GLOBAL_API_URL="https://api.anthropic.com"
      GLOBAL_API_FORMAT="anthropic-messages"; GLOBAL_MODEL_ID="claude-sonnet-4-6"
      ;;
    2)
      GLOBAL_PROVIDER="openai"; GLOBAL_API_URL="https://api.openai.com/v1"
      GLOBAL_API_FORMAT="openai"; GLOBAL_MODEL_ID="gpt-4o"
      ;;
    3)
      GLOBAL_PROVIDER="deepseek"; GLOBAL_API_URL="https://api.deepseek.com/v1"
      GLOBAL_API_FORMAT="openai"; GLOBAL_MODEL_ID="deepseek-chat"
      ;;
    *) info "不设置全局默认，逐个配置" ;;
  esac

  if [ -n "$GLOBAL_MODEL_ID" ]; then
    echo ""
    read -s -p "全局默认 API Key: " GLOBAL_API_KEY </dev/tty
    echo ""
  fi

  # 全局默认设置完后，再逐 Agent 配置
  echo ""
  info "开始为每个 Agent 配置模型..."
  echo ""

  for agent_id in $(echo "$SELECTED_AGENTS" | tr ',' ' '); do
    agent_model_pick "$agent_id"
  done

  echo ""
  ok "Agent 模型配置完成"
}

# 单个 Agent 模型选择
agent_model_pick() {
  _clear
  local agent_id="$1"
  local agent_name="$(_agent_display_name "$agent_id")"
  local current="${AGENT_MODEL_MAP[$agent_id]:-未配置}"

  echo ""
  echo -e "  ${CYAN}┌────────────────────────────────────────────────────────┐${NC}"
  echo -e "  ${CYAN}│${NC}  ${BOLD}Agent 模型配置${NC}                                       ${CYAN}│${NC}"
  echo -e "  ${CYAN}└────────────────────────────────────────────────────────┘${NC}"
  echo -e "  ${CYAN}  ${BOLD}[$agent_name · $agent_id]${NC}"
  echo -e "  ${CYAN}  当前：$current${NC}"
  echo ""
  echo "   1) Anthropic  claude-sonnet-4-6"
  echo "   2) OpenAI    gpt-4o"
  echo "   3) DeepSeek  deepseek-chat"
  echo "   4) OpenAI    gpt-4o-mini（快速）"
  echo "   5) Anthropic claude-haiku-4-5（轻量）"
  echo "   6) OpenRouter（选具体模型）"
  echo "   7) 使用全局默认（$GLOBAL_MODEL_ID）"
  echo "   8) 跳过（稍后配置）"
  echo ""

  # 翰林院批量快捷选项
  if [[ "$agent_id" == "hanlin_zhang" ]]; then
    echo "  [翰林院部门] 快捷选项："
    echo "   A) 翰林院全部 5 agents 使用 DeepSeek"
    echo "   B) 翰林院全部 5 agents 使用 GPT-4o"
    echo "   C) 逐个配置"
    echo ""
  fi

  read -p "请选择 [1-8/A/B/C]: " choice </dev/tty

  case "$choice" in
    1) AGENT_MODEL_MAP[$agent_id]="anthropic/claude-sonnet-4-6" ;;
    2) AGENT_MODEL_MAP[$agent_id]="openai/gpt-4o" ;;
    3) AGENT_MODEL_MAP[$agent_id]="deepseek/deepseek-chat" ;;
    4) AGENT_MODEL_MAP[$agent_id]="openai/gpt-4o-mini" ;;
    5) AGENT_MODEL_MAP[$agent_id]="anthropic/claude-haiku-4-5" ;;
    6) AGENT_MODEL_MAP[$agent_id]="$(agent_openrouter_pick)" ;;
    7)
      if [ -n "$GLOBAL_MODEL_ID" ]; then
        AGENT_MODEL_MAP[$agent_id]="${GLOBAL_PROVIDER}/${GLOBAL_MODEL_ID}"
      else
        warn "全局默认未设置，跳过"
      fi
      ;;
    8) : ;;  # 跳过
    A|a) _hanlin_batch "deepseek/deepseek-chat"; return ;;
    B|b) _hanlin_batch "openai/gpt-4o"; return ;;
    C|c) : ;;
    *) warn "无效选择" ;;
  esac

  if [ -n "${AGENT_MODEL_MAP[$agent_id]}" ]; then
    ok "已配置：${AGENT_MODEL_MAP[$agent_id]}"
  fi
}

# 翰林院批量配置
_hanlin_batch() {
  local model_ref="$1"
  local hanlin_agents="hanlin_zhang,hanlin_xiuzhuan,hanlin_bianxiu,hanlin_jiantao,hanlin_shujishi"
  for a in $(echo "$hanlin_agents" | tr ',' ' '); do
    AGENT_MODEL_MAP[$a]="$model_ref"
  done
  ok "翰林院 5 agents 全部设为：$model_ref"
}

# OpenRouter 模型选择
agent_openrouter_pick() {
  echo ""
  info "OpenRouter 常用模型："
  local i=1
  for entry in "${OPENROUTER_MODELS[@]}"; do
    local model_id="${entry%%:*}"
    local model_name="${entry#*:}"
    echo "   $i) $model_name"
    openrouter_index[$i]="$model_id"
    i=$((i + 1))
  done
  echo ""
  read -p "请选择 [1-$(($i-1))]: " choice </dev/tty
  local idx="${openrouter_index[$choice]:-}"
  if [ -n "$idx" ]; then
    echo "openrouter/${idx}"
  else
    echo ""
  fi
}

# 获取 agent 显示名
_agent_display_name() {
  local agent_id="$1"
  case "$agent_id" in
    silijian)     echo "司礼监" ;;
    neige)        echo "内阁" ;;
    libu2)        echo "吏部" ;;
    hubu)         echo "户部" ;;
    bingbu)       echo "兵部" ;;
    libu)         echo "礼部" ;;
    xingbu)       echo "刑部" ;;
    gongbu)       echo "工部" ;;
    duchayuan)    echo "都察院" ;;
    dianbosi)     echo "典簿司" ;;
    hanlin_zhang)    echo "翰林院·掌院学士" ;;
    hanlin_xiuzhuan) echo "翰林院·修撰" ;;
    hanlin_bianxiu)  echo "翰林院·编修" ;;
    hanlin_jiantao) echo "翰林院·检讨" ;;
    hanlin_shujishi) echo "翰林院·庶吉士" ;;
    qijuzhu)      echo "起居注官" ;;
    guozijian)    echo "国子监" ;;
    taiyiyuan)    echo "太医院" ;;
    neiwufu)      echo "内务府" ;;
    yushanfang)   echo "御膳房" ;;
    *)            echo "$agent_id" ;;
  esac
}

declare -A openrouter_index

# ============================================
# 步骤3：执行安装
# ============================================
do_install() {
  banner "③ 执行安装"

  # 环境检查
  echo ""
  info "检查环境..."

  if ! command -v jq &>/dev/null; then
    warn "jq 未安装，正在安装..."
    if command -v brew &>/dev/null; then
      brew install jq
    elif command -v apt &>/dev/null; then
      sudo apt install -y jq
    else
      fail "无法自动安装 jq，请手动安装后重试"
      exit 1
    fi
  fi

  if ! command -v openclaw &>/dev/null; then
    warn "OpenClaw 未安装，正在安装..."
    npm install -g openclaw@latest
  fi
  ok "环境检查通过"

  # 模板路径
  local template_config="$PROJECT_ROOT/configs/ming-neige/openclaw.json"
  if [ ! -f "$template_config" ]; then
    fail "模板文件不存在：$template_config"
    exit 1
  fi

  # CONFIG_DIR 初始化
  detect_config_dir
  mkdir -p "$CONFIG_DIR"
  mkdir -p "$CONFIG_DIR/agents"

  local config_file="$CONFIG_DIR/openclaw.json"

  # 备份现有配置
  if [ -f "$config_file" ]; then
    local backup="${config_file}.$(date +%Y%m%d_%H%M%S).bak"
    cp "$config_file" "$backup"
    ok "已备份现有配置：$backup"
    # 提取已有 Discord Token
    EXISTING_TOKENS=$(jq '.channels.discord.accounts |
      to_entries |
      map({ key: .key, value: { token: .value.token } }) |
      from_entries' "$config_file" 2>/dev/null || echo "{}")
  else
    EXISTING_TOKENS="{}"
  fi

  # 复制模板
  echo ""
  info "生成配置..."
  cp "$template_config" "$config_file"

  # ---- 过滤 agents.list ----
  # 从模板提取全部 agents，再按 selected_agents 过滤
  local total=$(jq '.agents.list | length' "$config_file")
  local tmp_file="${config_file}.tmp.$$"

  # 用 jq 删除不在 selected_agents 中的 agent
  jq --argjson agents_list "$(jq -c '.agents.list' "$config_file")" \
     --arg selected "$SELECTED_AGENTS" '
     def split_unique: [splits(" |,|  ")] | map(select(length > 0));
     def wanted: ($selected | split_unique | map(.) | unique);
     .agents.list = ($agents_list | map(select(.id | IN(wanted[]))))
     ' "$config_file" > "$tmp_file" && mv "$tmp_file" "$config_file"

  local installed_count=$(jq '.agents.list | length' "$config_file")
  ok "Agent 列表已过滤：$installed_count 个"

  # ---- 注入人设文件 ----
  echo ""
  info "下载 Agent 人设..."
  local failed=0
  for agent_id in $(echo "$SELECTED_AGENTS" | tr ',' ' '); do
    local persona_src="$PROJECT_ROOT/configs/ming-neige/agents/${agent_id}.md"
    local persona_dest="$CONFIG_DIR/agents/${agent_id}.md"
    if [ -f "$persona_src" ]; then
      cp "$persona_src" "$persona_dest"
      # 注入 identity.theme（跳过文件头 2 行元信息）
      local persona=$(tail -n +3 "$persona_src" | jq -Rs '.')
      local idx=$(jq --arg id "$agent_id" \
        '[.agents.list | to_entries[] | select(.value.id == $id) | .key] | .[0]' \
        "$config_file" 2>/dev/null || echo "null")
      if [ "$idx" != "null" ]; then
        jq --argjson i "$idx" --argjson p "$persona" \
          '.agents.list[$i].identity.theme = $p' \
          "$config_file" > "$tmp_file" && mv "$tmp_file" "$config_file"
      fi
      ok "$agent_id"
    else
      warn "$agent_id (无独立人设文件，跳过)"
      failed=$((failed + 1))
    fi
  done

  # ---- 注入模型配置 ----
  echo ""
  if [ "$MODEL_MODE" == "unified" ] && [ -n "$GLOBAL_API_KEY" ]; then
    info "配置统一模型：$GLOBAL_PROVIDER / $GLOBAL_MODEL_ID"
    inject_unified_model "$config_file"
  elif [ "$MODEL_MODE" == "per-agent" ] && [ -n "$GLOBAL_API_KEY" ]; then
    info "配置全局默认 + Agent 专属模型..."
    inject_unified_model "$config_file"
    inject_per_agent_models "$config_file"
  elif [ "$MODEL_MODE" == "per-agent" ]; then
    info "仅配置 Agent 模型引用（API Key 需后续填写）..."
    inject_per_agent_models "$config_file"
  else
    info "跳过模型配置"
  fi

  # ---- 保留已有 Discord Token ----
  if [ "$EXISTING_TOKENS" != "{}" ] && [ -n "$EXISTING_TOKENS" ]; then
    echo ""
    info "保留已有 Discord Token..."
    jq --argjson tokens "$EXISTING_TOKENS" \
      '.channels.discord.accounts |= . * $tokens' \
      "$config_file" > "$tmp_file" && mv "$tmp_file" "$config_file"
    ok "已有 Token 已保留"
  fi

  # ---- 验证 JSON ----
  echo ""
  if jq empty "$config_file" 2>/dev/null; then
    ok "配置验证通过"
  else
    fail "配置 JSON 格式错误！"
    exit 1
  fi

  # ---- 保存安装状态 ----
  state_save "CONFIG_DIR" "$CONFIG_DIR"
  state_save "SELECTED_REGIME" "ming-neige"
  state_save "INSTALLED_DEPARTMENTS" "$SELECTED_DEPT"
  state_save "MODEL_MODE" "$MODEL_MODE"

  # 保存 Agent 模型映射
  if [ "$MODEL_MODE" == "per-agent" ]; then
    for aid in "${!AGENT_MODEL_MAP[@]}"; do
      state_save "AGENT_MODEL_${aid}" "${AGENT_MODEL_MAP[$aid]}"
    done
  fi

  ok "配置状态已保存：$CFG_FILE"
  echo ""
  ok "安装完成！配置文件：$config_file"
}

# 注入统一模型
inject_unified_model() {
  local cfg="$1"
  local tmp="${cfg}.tmp.$$"

  # 构建 models 数组
  local models_json="[{\"id\":\"${GLOBAL_MODEL_ID}\",\"name\":\"${GLOBAL_MODEL_ID}\",\"input\":[\"text\"],\"contextWindow\":200000,\"maxTokens\":8192}]"

  jq --arg provider "$GLOBAL_PROVIDER" \
     --arg baseUrl "$GLOBAL_API_URL" \
     --arg apiKey "$GLOBAL_API_KEY" \
     --arg api "$GLOBAL_API_FORMAT" \
     --argjson models "$models_json" \
     '.models.providers[$provider] = {
         baseUrl: $baseUrl,
         apiKey: $apiKey,
         api: $api,
         models: $models
     }' "$cfg" > "$tmp" && mv "$tmp" "$cfg"

  # 更新所有 Agent 的 model.primary
  local ref="${GLOBAL_PROVIDER}/${GLOBAL_MODEL_ID}"
  jq --arg ref "$ref" \
     '(.agents.list | map(.model.primary = $ref)) as $new |
      .agents.list = $new' \
     "$cfg" > "$tmp" && mv "$tmp" "$cfg"

  ok "统一模型已注入：$ref"
}

# 注入分 Agent 模型
inject_per_agent_models() {
  local cfg="$1"
  local tmp="${cfg}.tmp.$$"
  local registered_providers=""

  for agent_id in $(echo "$SELECTED_AGENTS" | tr ',' ' '); do
    local model_ref="${AGENT_MODEL_MAP[$agent_id]:-}"
    [ -z "$model_ref" ] && continue

    local provider="${model_ref%%/*}"
    local model_id="${model_ref#*/}"

    # 检查 provider 是否已注册
    if ! jq -e ".models.providers[\"$provider\"]" "$cfg" &>/dev/null; then
      # 未注册，新增（使用模板中的通用注册方式）
      jq --arg p "$provider" \
         --arg baseUrl "$(provider_default_url "$provider")" \
         --arg api "$(provider_default_api "$provider")" \
         --arg model "$model_id" \
         '.models.providers[$p] = {
             baseUrl: $baseUrl,
             apiKey: "",
             api: $api,
             models: [{
                 id: $model,
                 name: $model,
                 input: ["text"],
                 contextWindow: 200000,
                 maxTokens: 8192
             }]
         }' "$cfg" > "$tmp" && mv "$tmp" "$cfg"
    fi

    # 更新 Agent 的 model.primary
    local idx=$(jq --arg id "$agent_id" \
      '[.agents.list | to_entries[] | select(.value.id == $id) | .key] | .[0]' \
      "$cfg" 2>/dev/null || echo "null")
    if [ "$idx" != "null" ]; then
      jq --argjson i "$idx" --arg ref "$model_ref" \
        '.agents.list[$i].model.primary = $ref' \
        "$cfg" > "$tmp" && mv "$tmp" "$cfg"
    fi
  done
}

# Provider 默认 URL
provider_default_url() {
  case "$1" in
    anthropic)  echo "https://api.anthropic.com" ;;
    openai)     echo "https://api.openai.com/v1" ;;
    deepseek)   echo "https://api.deepseek.com/v1" ;;
    openrouter) echo "https://openrouter.ai/api/v1" ;;
    ollama)     echo "http://localhost:11434/v1" ;;
    *)          echo "" ;;
  esac
}

# Provider 默认 API format
provider_default_api() {
  case "$1" in
    anthropic)  echo "anthropic-messages" ;;
    *)          echo "openai" ;;
  esac
}

# ============================================
# 配置流程
# ============================================
config_flow() {
  banner "配置流程"
  echo ""

  detect_config_dir
  local cfg="$CONFIG_DIR/openclaw.json"

  if [ ! -f "$cfg" ]; then
    fail "配置文件不存在，请先运行安装流程（选项 1）"
    echo ""
    warn "提示：bash scripts/interactive-install.sh → 1 安装"
    pause
    main_menu
    return
  fi

  # 读取已安装的 Agent
  local agent_ids=$(jq -r '.agents.list[].id' "$cfg" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
  if [ -z "$agent_ids" ]; then
    fail "配置文件中无 Agent，请重新安装"
    pause
    main_menu
    return
  fi

  echo "  已安装的 Agent（共 $(echo "$agent_ids" | tr ',' '\n' | grep -c .) 个）："
  echo ""
  for aid in $(echo "$agent_ids" | tr ',' ' '); do
    local name=$(_agent_display_name "$aid")
    local token_status
    local existing=$(jq -r ".channels.discord.accounts[\"$aid\"].token // \"\" " "$cfg" 2>/dev/null)
    if [ -n "$existing" ] && [ "$existing" != "YOUR_${aid^^}_BOT_TOKEN" ] && [ "${#existing}" -gt 20 ]; then
      token_status="${GREEN}已配置${NC}"
    else
      token_status="${YELLOW}未配置${NC}"
    fi
    printf "    %-20s %b\n" "$name ($aid)" "$token_status"
  done
  echo ""

  # 选择要配置的 Agent
  echo "  请输入要配置的 Agent ID（支持空格分隔多个）："
  read -p "  (直接 Enter 配置全部): " input </dev/tty

  if [ -z "$input" ]; then
    AGENTS_TO_CONFIG=$(echo "$agent_ids" | tr ',' ' ')
  else
    AGENTS_TO_CONFIG="$input"
  fi

  echo ""
  info "开始配置 Discord Token..."
  echo ""

  for aid in $AGENTS_TO_CONFIG; do
    discord_config_agent "$aid" "$cfg"
  done

  echo ""
  ok "Discord Token 配置完成！"
  echo ""
  echo "  下一步："
  echo "    openclaw gateway start"
  echo "    openclaw status"
  echo ""
  pause
  main_menu
}

# 配置单个 Agent 的 Discord Token
discord_config_agent() {
  _clear
  local agent_id="$1"
  local cfg="$2"
  local name=$(_agent_display_name "$agent_id")
  local existing=$(jq -r ".channels.discord.accounts[\"$agent_id\"].token // \"\" " "$cfg" 2>/dev/null)

  echo ""
  echo -e "  ${CYAN}┌────────────────────────────────────────────────────────┐${NC}"
  echo -e "  ${CYAN}│${NC}  ${BOLD}Discord Token 配置${NC}                                   ${CYAN}│${NC}"
  echo -e "  ${CYAN}└────────────────────────────────────────────────────────┘${NC}"
  echo -e "  ${CYAN}  [${name} · ${agent_id}]${NC}"
  echo ""

  # Token 掩码显示
  if [ -n "$existing" ] && [ "${#existing}" -gt 20 ] && [ "$existing" != "YOUR_${agent_id^^}_BOT_TOKEN" ]; then
    local masked="${existing:0:6}...${existing: -4}"
    echo "  Token: $masked（已有）"
  else
    echo "  Token: ${YELLOW}未配置${NC}"
  fi
  echo ""
  echo "   1) 输入新 Token"
  echo "   2) 跳过"
  echo ""

  read -p "请选择 [1/2]: " choice </dev/tty
  case "$choice" in
    1)
      echo ""
      read -s -p "  请输入 Discord Bot Token（输入时不可见）: " new_token </dev/tty
      echo ""
      if [ -z "$new_token" ]; then
        warn "Token 为空，跳过"
      else
        local tmp="${cfg}.tmp.$$"
        # 检查 account 是否存在，不存在则创建
        if jq -e ".channels.discord.accounts[\"$agent_id\"]" "$cfg" &>/dev/null; then
          jq --argjson tok "$new_token" \
            ".channels.discord.accounts[\"$agent_id\"].token = \$tok" \
            "$cfg" > "$tmp" && mv "$tmp" "$cfg"
        else
          jq --argjson tok "$new_token" --argjson name "$name" \
            ".channels.discord.accounts[\"$agent_id\"] = {
               name: \$name,
               token: \$tok,
               groupPolicy: \"open\"
             }" \
            "$cfg" > "$tmp" && mv "$tmp" "$cfg"
        fi
        ok "Token 已更新"
      fi
      ;;
    2) info "跳过"; ;;
    *) warn "无效选择" ;;
  esac
  echo ""
}

# ============================================
# 入口
# ============================================
main() {
  detect_config_dir
  main_menu
}

main "$@"
