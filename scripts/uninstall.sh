#!/bin/bash
# ============================================
# 御书房 · 完整卸载脚本
#
# 用法：
#   bash scripts/uninstall.sh
#
# 支持 Docker 和非 Docker 两种部署方式的完整清理
# ============================================

set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
echo -e "${CYAN}║    🏯 御书房 · 完整卸载             ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
echo ""

# ---- 确认操作 ----
echo -e "${YELLOW}⚠️  此操作将删除以下内容：${NC}"
echo ""
echo "  1. OpenClaw / ClawdHub 全局 npm 包"
echo "  2. ~/.openclaw / ~/.clawdbot 配置目录"
echo "  3. ~/clawd 工作目录及所有 agent 工作区"
echo "  4. ~/clawd-hubu/ 户部数据（如有）"
echo "  5. Docker 容器、镜像、数据卷（如适用）"
echo "  6. crontab 中的 OpenClaw/Yushufang 任务"
echo "  7. Discord Bot Token（需手动在 Developer Portal 撤销）"
echo ""
echo -e "${YELLOW}⚠️  ${BOLD}数据删除后不可恢复，请提前备份！${NC}"
echo ""

read -p "确认卸载？(y/n): " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
  echo -e "${CYAN}已取消卸载。${NC}"
  exit 0
fi

echo ""

# ============================================
# 第一步：停止运行中的服务
# ============================================
echo -e "${CYAN}[1/6] 停止服务...${NC}"

# 非 Docker 模式
if command -v openclaw &>/dev/null; then
  echo "  停止 OpenClaw Gateway..."
  openclaw gateway stop 2>/dev/null || true
  echo -e "  ${GREEN}✓${NC} Gateway 已停止"
else
  echo -e "  ${YELLOW}i${NC} OpenClaw 未安装，跳过"
fi

# Docker 模式
if command -v docker &>/dev/null; then
  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qE "ai-court|yushufang|danghuangshang"; then
    echo "  停止 Docker 容器..."
    docker compose down 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} Docker 容器已停止"
  else
    echo -e "  ${YELLOW}i${NC} 未发现御书房相关容器，跳过"
  fi
else
  echo -e "  ${YELLOW}i${NC} Docker 未安装，跳过"
fi

echo ""

# ============================================
# 第二步：卸载全局 npm 包
# ============================================
echo -e "${CYAN}[2/6] 卸载全局 npm 包...${NC}"

if command -v npm &>/dev/null; then
  if npm list -g --depth=0 2>/dev/null | grep -q "openclaw"; then
    npm uninstall -g openclaw 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} openclaw 已卸载"
  else
    echo -e "  ${YELLOW}i${NC} openclaw 未通过 npm 安装，跳过"
  fi

  if npm list -g --depth=0 2>/dev/null | grep -q "clawdhub"; then
    npm uninstall -g clawdhub 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} clawdhub 已卸载"
  else
    echo -e "  ${YELLOW}i${NC} clawdhub 未安装，跳过"
  fi
else
  echo -e "  ${YELLOW}i${NC} npm 未安装，跳过"
fi

echo ""

# ============================================
# 第三步：删除配置目录
# ============================================
echo -e "${CYAN}[3/6] 删除配置目录...${NC}"

# ~/.openclaw
if [ -d "$HOME/.openclaw" ]; then
  rm -rf "$HOME/.openclaw"
  echo -e "  ${GREEN}✓${NC} 已删除 ~/.openclaw"
else
  echo -e "  ${YELLOW}i${NC} ~/.openclaw 不存在，跳过"
fi

# ~/.clawdbot
if [ -d "$HOME/.clawdbot" ]; then
  rm -rf "$HOME/.clawdbot"
  echo -e "  ${GREEN}✓${NC} 已删除 ~/.clawdbot"
else
  echo -e "  ${YELLOW}i${NC} ~/.clawdbot 不存在，跳过"
fi

echo ""

# ============================================
# 第四步：删除工作目录
# ============================================
echo -e "${CYAN}[4/6] 删除工作目录...${NC}"

# ~/clawd
if [ -d "$HOME/clawd" ]; then
  rm -rf "$HOME/clawd"
  echo -e "  ${GREEN}✓${NC} 已删除 ~/clawd"
else
  echo -e "  ${YELLOW}i${NC} ~/clawd 不存在，跳过"
fi

# ~/clawd-* (各 agent 工作区)
if ls -d "$HOME"/clawd-* 2>/dev/null | grep -q .; then
  for dir in "$HOME"/clawd-*; do
    [ -d "$dir" ] && rm -rf "$dir" && echo -e "  ${GREEN}✓${NC} 已删除 $dir"
  done
else
  echo -e "  ${YELLOW}i${NC} 无 clawd-* 子目录，跳过"
fi

# ~/clawd-hubu
if [ -d "$HOME/clawd-hubu" ]; then
  rm -rf "$HOME/clawd-hubu"
  echo -e "  ${GREEN}✓${NC} 已删除 ~/clawd-hubu"
else
  echo -e "  ${YELLOW}i${NC} ~/clawd-hubu 不存在，跳过"
fi

echo ""

# ============================================
# 第五步：清理 Docker（如适用）
# ============================================
echo -e "${CYAN}[5/6] 清理 Docker...${NC}"

if command -v docker &>/dev/null; then
  # 删除御书房相关容器
  CONTAINERS=$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -iE "ai-court|yushufang|danghuangshang" || true)
  if [ -n "$CONTAINERS" ]; then
    echo "$CONTAINERS" | xargs docker rm -f 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} 相关容器已删除"
  fi

  # 删除御书房相关镜像
  IMAGES=$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -iE "ai-court|yushufang|danghuangshang|boluobobo" || true)
  if [ -n "$IMAGES" ]; then
    echo "$IMAGES" | xargs docker rmi -f 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} 相关镜像已删除"
  fi

  # 删除 Docker 数据卷
  VOLUMES=$(docker volume ls --format '{{.Name}}' 2>/dev/null | grep -iE "yushufang|danghuangshang|clawd" || true)
  if [ -n "$VOLUMES" ]; then
    echo "$VOLUMES" | xargs docker volume rm 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} 相关数据卷已删除"
  fi

  echo -e "  ${YELLOW}i${NC} 如有自定义 Docker Compose 配置，请手动运行 docker compose down -v"
else
  echo -e "  ${YELLOW}i${NC} Docker 未安装，跳过"
fi

echo ""

# ============================================
# 第六步：清理 crontab
# ============================================
echo -e "${CYAN}[6/6] 清理 crontab...${NC}"

if command -v openclaw &>/dev/null; then
  # 列出当前 OpenClaw cron 任务
  CRON_LIST=$(openclaw cron list 2>/dev/null || true)
  if [ -n "$CRON_LIST" ]; then
    echo -e "  ${YELLOW}检测到以下 OpenClaw cron 任务，请手动删除：${NC}"
    echo "$CRON_LIST" | sed 's/^/    /'
  else
    echo -e "  ${YELLOW}i${NC} 无 OpenClaw cron 任务"
  fi
fi

# 清理 crontab 中的御书房相关条目
if crontab -l 2>/dev/null | grep -qE "yushufang|danghuangshang|clawd|hubu-data-collect"; then
  crontab -l 2>/dev/null | grep -vE "yushufang|danghuangshang|clawd|hubu-data-collect" | crontab - 2>/dev/null || true
  echo -e "  ${GREEN}✓${NC} crontab 中御书房相关条目已清理"
else
  echo -e "  ${YELLOW}i${NC} crontab 中无御书房相关条目"
fi

echo ""

# ============================================
# 完成
# ============================================
echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║    ✓ 御书房已完全卸载                 ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}⚠️  以下操作需要您手动完成：${NC}"
echo ""
echo "  1. Discord Developer Portal：撤销 Bot Application，删除相关 Application"
echo "     https://discord.com/developers/applications"
echo ""
echo "  2. 如使用飞书/其他第三方集成，请在对应平台撤销授权"
echo ""
echo "  3. 如有数据备份需求，请在重新安装前从备份恢复"
echo ""
echo -e "感谢使用御书房！如需重新安装，请参考：${CYAN}https://github.com/1012Lonin/Yushufang${NC}"
echo ""
