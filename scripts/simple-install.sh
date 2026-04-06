#!/bin/bash
# ============================================
# 御书房 · 简化安装脚本
# 用法：bash <(curl -fsSL https://raw.githubusercontent.com/1012Lonin/Yushufang/main/scripts/simple-install.sh)
# ============================================

set -euo pipefail
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════╗${NC}"
echo -e "${CYAN}║   AI 朝廷 · 快速安装     ║${NC}"
echo -e "${CYAN}╚══════════════════════════╝${NC}"
echo ""

# 步骤 1: 检查 OpenClaw
echo -e "${BLUE}[1/4] 检查环境...${NC}"
if ! command -v openclaw &>/dev/null; then
  echo -e "${YELLOW}⚠ OpenClaw 未安装，正在安装...${NC}"
  npm install -g openclaw@latest
fi
echo -e "${GREEN}✓${NC} OpenClaw 已安装"

# 步骤 2: 配置 LLM API
echo -e "${BLUE}[2/4] 配置 AI 模型...${NC}"
echo ""
echo "常用 API 提供商："
echo "  - DeepSeek: https://platform.deepseek.com"
echo "  - OpenAI: https://platform.openai.com"
echo "  - Anthropic: https://console.anthropic.com"
echo ""
read -p "API Base URL (如 https://api.deepseek.com/v1): " API_URL
read -s -p "API Key: " API_KEY
echo ""
read -p "模型 ID (如 deepseek-chat, gpt-4o): " MODEL_ID
echo ""

if [ -z "$API_URL" ] || [ -z "$API_KEY" ] || [ -z "$MODEL_ID" ]; then
    echo -e "${RED}✗ API 配置不能为空${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} API 配置完成"

# 步骤 3: 选择制度
echo -e "${BLUE}[3/4] 选择制度...${NC}"
echo "  1) 明朝内阁制 (推荐)"
echo "  2) 唐朝三省制"
echo "  3) 现代企业制"
read -p "  请选择 [1-3]: " choice
case "$choice" in
  1) REGIME="ming-neige" ;;
  2) REGIME="tang-sansheng" ;;
  3) REGIME="modern-ceo" ;;
  *) echo -e "${RED}✗ 无效选择${NC}"; exit 1 ;;
esac

# 步骤 4: 安装配置
echo -e "${BLUE}[4/4] 安装配置...${NC}"

# 支持 CONFIG_DIR 环境变量覆盖（Docker 等非标准路径）
# 同时检测双安装并报错，避免误覆盖
if [ -z "${CONFIG_DIR:-}" ]; then
  CLAWDBOT_CONFIG="$HOME/.clawdbot/openclaw.json"
  OPENCLAW_CONFIG="$HOME/.openclaw/openclaw.json"
  if [ -f "$CLAWDBOT_CONFIG" ] && [ -f "$OPENCLAW_CONFIG" ]; then
    echo -e "${RED}✗ 错误：~/.openclaw 和 ~/.clawdbot 同时存在${NC}" >&2
    echo "  请明确指定：CONFIG_DIR=~/.openclaw 或 CONFIG_DIR=~/.clawdbot bash $0" >&2
    exit 1
  elif [ -f "$CLAWDBOT_CONFIG" ]; then
    CONFIG_DIR="$HOME/.clawdbot"
    echo -e "  ${YELLOW}i${NC} 使用 .clawdbot 配置目录"
  elif [ -f "$OPENCLAW_CONFIG" ]; then
    CONFIG_DIR="$HOME/.openclaw"
    echo -e "  ${YELLOW}i${NC} 使用 .openclaw 配置目录"
  else
    CONFIG_DIR="$HOME/.openclaw"
    echo -e "  ${YELLOW}i${NC} 将创建新配置"
  fi
else
  echo -e "  ${YELLOW}i${NC} 使用 CONFIG_DIR: $CONFIG_DIR"
fi

mkdir -p "$CONFIG_DIR"

# 备份现有配置（如果有）
if [ -f "$CONFIG_DIR/openclaw.json" ]; then
  BACKUP_FILE="$CONFIG_DIR/openclaw.json.$(date +%Y%m%d_%H%M%S).bak"
  cp "$CONFIG_DIR/openclaw.json" "$BACKUP_FILE"
  echo -e "  ${YELLOW}✓${NC} 已备份现有配置：$BACKUP_FILE"
fi

# 下载配置（先下载以获取 agent 列表）
TEMPLATE_URL="https://raw.githubusercontent.com/1012Lonin/Yushufang/main/configs/$REGIME/openclaw.json"
TEMP_CONFIG="${CONFIG_DIR}/openclaw.json.download.$$"
echo -e "  ${CYAN}下载配置模板...${NC}"
if ! curl -fsSL "$TEMPLATE_URL" -o "$TEMP_CONFIG" 2>/dev/null; then
  echo -e "  ${RED}✗ 下载配置模板失败${NC}"
  rm -f "$TEMP_CONFIG"
  if [ -f "${BACKUP_FILE:-}" ]; then
    cp "$BACKUP_FILE" "$CONFIG_DIR/openclaw.json"
    echo -e "  ${YELLOW}✓${NC} 已恢复原配置"
  fi
  exit 1
fi

# 验证模板 JSON 有效
if ! jq empty "$TEMP_CONFIG" 2>/dev/null; then
  echo -e "  ${RED}✗ 配置模板无效${NC}"
  rm -f "$TEMP_CONFIG"
  exit 1
fi

# 从模板动态提取 agent 列表（修复：不再硬编码 8 个）
AGENT_LIST=$(jq -r '.agents.list[].id' "$TEMP_CONFIG" 2>/dev/null)
if [ -z "$AGENT_LIST" ]; then
  echo -e "  ${RED}✗ 无法从模板提取 agent 列表${NC}"
  rm -f "$TEMP_CONFIG"
  exit 1
fi
AGENT_COUNT=$(echo "$AGENT_LIST" | wc -l | tr -d ' ')
echo -e "  ${YELLOW}i${NC} 检测到 $AGENT_COUNT 个 Agent"

# 下载人设文件
echo -e "  ${CYAN}下载 Agent 人设...${NC}"
mkdir -p "$CONFIG_DIR/agents"
while IFS= read -r agent_id; do
  curl -fsSL "https://raw.githubusercontent.com/1012Lonin/Yushufang/main/configs/$REGIME/agents/${agent_id}.md" \
    -o "$CONFIG_DIR/agents/${agent_id}.md" 2>/dev/null && echo -e "    ${GREEN}✓${NC} $agent_id" || echo -e "    ${YELLOW}⚠${NC} $agent_id (无独立人设)"
done <<< "$AGENT_LIST"
echo -e "  ${GREEN}✓${NC} Agent 人设下载完成"

# 移动模板到目标位置
mv "$TEMP_CONFIG" "$CONFIG_DIR/openclaw.json"

# 使用 Python 更新 LLM 配置
python3 << PYEOF
import json

config_file = "$CONFIG_DIR/openclaw.json"

with open(config_file, 'r') as f:
    config = json.load(f)

# 更新 models 配置
config['models'] = {
    'providers': {
        'your-provider': {
            'baseUrl': '$API_URL',
            'apiKey': '$API_KEY',
            'api': 'openai',
            'models': [{'id': '$MODEL_ID', 'name': '主模型', 'input': ['text', 'image'], 'contextWindow': 200000, 'maxTokens': 8192}]
        }
    }
}

with open(config_file, 'w') as f:
    json.dump(config, f, indent=2)

print(f"✓ LLM 配置已更新")
PYEOF

# 验证修改后的配置 JSON 有效
if ! jq empty "$CONFIG_DIR/openclaw.json" 2>/dev/null; then
  echo -e "  ${RED}✗ 配置验证失败（JSON 格式错误）${NC}"
  if [ -n "${BACKUP_FILE:-}" ] && [ -f "$BACKUP_FILE" ]; then
    cp "$BACKUP_FILE" "$CONFIG_DIR/openclaw.json"
    echo -e "  ${YELLOW}✓${NC} 已恢复原配置"
  fi
  exit 1
fi
echo -e "  ${GREEN}✓${NC} 配置已安装：$CONFIG_DIR/openclaw.json"

echo ""
echo -e "${GREEN}╔══════════════════════════╗${NC}"
echo -e "${GREEN}║   安装完成！             ║${NC}"
echo -e "${GREEN}╚══════════════════════════╝${NC}"
echo ""
echo "下一步："
echo "  1. 编辑配置（如需要）：nano $CONFIG_DIR/openclaw.json"
echo "  2. 填入平台凭证 (飞书 AppID/Secret 或 Discord Token)"
echo "  3. 启动：openclaw gateway start"
echo ""
