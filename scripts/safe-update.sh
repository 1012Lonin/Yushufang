#!/bin/bash
#
# safe-update.sh - 御书房安全更新脚本
# 
# 功能：
# 1. 更新前自动备份配置和记忆
# 2. 检查关键安全配置
# 3. 支持一键回滚
#
# 用法：
#   ./safe-update.sh          # 完整流程（备份 + 检查 + 更新）
#   ./safe-update.sh --backup # 仅备份
#   ./safe-update.sh --check  # 仅安全检查
#   ./safe-update.sh --rollback  # 回滚到上次备份
#

set -euo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 路径配置：优先使用环境变量（operator 覆盖），否则自动检测
if [ -n "${CLAWD_DIR:-}" ]; then
  : # operator override，保留原值
elif [ -f "$HOME/.openclaw/openclaw.json" ] && [ -f "$HOME/.clawdbot/openclaw.json" ]; then
  echo -e "${RED}✗ 错误：~/.openclaw 和 ~/.clawdbot 同时存在${NC}" >&2
  echo "  请明确指定配置目录：export CLAWD_DIR=~/.openclaw 或 export CLAWD_DIR=~/.clawdbot" >&2
  exit 1
elif [ -f "$HOME/.openclaw/openclaw.json" ]; then
  CLAWD_DIR="$HOME/.openclaw"
elif [ -f "$HOME/.clawdbot/openclaw.json" ]; then
  CLAWD_DIR="$HOME/.clawdbot"
else
  CLAWD_DIR="$HOME/.openclaw"
fi
# 打印函数（必须在使用前定义）
info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 路径配置：优先使用环境变量（operator 覆盖），否则自动检测
if [ -n "${CLAWD_DIR:-}" ]; then
  : # operator override，保留原值
elif [ -f "$HOME/.openclaw/openclaw.json" ] && [ -f "$HOME/.clawdbot/openclaw.json" ]; then
  echo -e "${RED}✗ 错误：~/.openclaw 和 ~/.clawdbot 同时存在${NC}" >&2
  echo "  请明确指定：export CLAWD_DIR=~/.openclaw 或 export CLAWD_DIR=~/.clawdbot" >&2
  exit 1
elif [ -f "$HOME/.openclaw/openclaw.json" ]; then
  CLAWD_DIR="$HOME/.openclaw"
elif [ -f "$HOME/.clawdbot/openclaw.json" ]; then
  CLAWD_DIR="$HOME/.clawdbot"
else
  CLAWD_DIR="$HOME/.openclaw"
fi
BACKUP_DIR="${BACKUP_DIR:-$CLAWD_DIR/backups}"
OPENCLAW_CONFIG="${OPENCLAW_CONFIG:-$CLAWD_DIR/openclaw.json}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# 打印已解析的配置目标
info "配置目录：$CLAWD_DIR"
info "配置文件：$OPENCLAW_CONFIG"

# 创建备份目录
init_backup_dir() {
    mkdir -p "$BACKUP_DIR"
    info "备份目录：$BACKUP_DIR"
}

# 备份配置
backup_configs() {
    local backup_path="$BACKUP_DIR/config_$TIMESTAMP"
    mkdir -p "$backup_path"
    
    info "正在备份配置..."
    
    # 备份 openclaw.json
    if [ -f "$OPENCLAW_CONFIG" ]; then
        cp "$OPENCLAW_CONFIG" "$backup_path/"
        success "已备份 openclaw.json"
    else
        warn "未找到 $OPENCLAW_CONFIG"
    fi
    
    # 备份 configs 目录（各制度配置）
    if [ -d "$CLAWD_DIR/configs" ]; then
        cp -r "$CLAWD_DIR/configs" "$backup_path/"
        success "已备份 configs/"
    fi
    
    # 备份 agents 目录
    if [ -d "$CLAWD_DIR/agents" ]; then
        cp -r "$CLAWD_DIR/agents" "$backup_path/"
        success "已备份 agents/"
    fi
    
    # 记录备份元数据
    echo "$TIMESTAMP" > "$backup_path/.timestamp"
    echo "$backup_path" > "$BACKUP_DIR/latest"
    
    success "备份完成：$backup_path"
}

# 安全检查
safety_check() {
    info "正在执行安全检查..."
    local errors=0

    # 检查 1: allowBots 设置（使用 jq，支持布尔型和字符串型）
    if [ -f "$OPENCLAW_CONFIG" ]; then
        if ! command -v jq >/dev/null 2>&1; then
            error "❌ jq 未安装，无法验证配置"
            ((errors++))
        elif ! jq empty "$OPENCLAW_CONFIG" 2>/dev/null; then
            error "❌ 配置文件 JSON 格式错误，无法继续安全检查"
            ((errors++))
        else
            local allow_bots
            allow_bots=$(jq -r '.channels.discord.allowBots // "not-set"' "$OPENCLAW_CONFIG" 2>/dev/null)

            case "$allow_bots" in
            mentions)
                success "allowBots=mentions（安全）"
                ;;
            false)
                success "allowBots=false（安全）"
                ;;
            true)
                error "❌ allowBots=true 危险！会导致机器人循环。请改为 \"mentions\""
                ((errors++))
                ;;
            not-set)
                warn "allowBots 未配置（建议设为 mentions）"
                ;;
            *)
                warn "allowBots=$allow_bots（请确认为 mentions 或 false）"
                ;;
        esac
        fi

        # 检查 2: mentionPatterns 是否包含 @everyone
        if grep -q '@everyone' "$OPENCLAW_CONFIG" 2>/dev/null; then
            error "❌ 发现 @everyone 配置！这是核弹开关，必须移除"
            ((errors++))
        else
            success "未发现 @everyone 配置"
        fi

        # 检查 3: mentionPatterns 是否包含 @here
        if grep -q '@here' "$OPENCLAW_CONFIG" 2>/dev/null; then
            error "❌ 发现 @here 配置！必须移除"
            ((errors++))
        else
            success "未发现 @here 配置"
        fi
    else
        error "❌ 未找到配置文件：$OPENCLAW_CONFIG"
        ((errors++))
    fi

    if [ $errors -gt 0 ]; then
        echo ""
        error "安全检查失败！发现 $errors 个严重问题，请修复后再更新"
    else
        success "安全检查通过 ✓"
    fi
}

# 执行更新
do_update() {
    local project_dir
    project_dir="$(dirname "$(dirname "$0")")"

    info "正在更新..."

    if [ -d "$project_dir/.git" ]; then
        info "Git 拉取：$project_dir"
        (cd "$project_dir" && git pull) || error "git pull 失败"
        success "git pull 完成"
    else
        warn "非 git 仓库，跳过拉取"
    fi

    # 重新注入人设（模板 → 运行时配置）
    if [ -f "$project_dir/scripts/init-personas.sh" ]; then
        info "重新注入人设..."
        (cd "$project_dir" && bash scripts/init-personas.sh) || warn "人设注入失败，请手动检查"
        success "人设注入完成"
    fi

    # 重启 Gateway
    if command -v openclaw &>/dev/null; then
        info "重启 Gateway..."
        openclaw gateway restart 2>/dev/null || warn "Gateway 重启失败，请手动重启"
        success "Gateway 重启完成"
    fi

    success "更新完成！"
}

# 回滚
rollback() {
    local backup_path=""
    local rollback_type=""

    # 方式一：safe-update.sh 自身备份（~/.openclaw/backups/latest）
    if [ -f "$BACKUP_DIR/latest" ] && [ -d "$(cat "$BACKUP_DIR/latest" 2>/dev/null)" ]; then
        backup_path=$(cat "$BACKUP_DIR/latest")
        rollback_type="safe-update"
        info "找到 safe-update 备份：$backup_path"

    # 方式二：backup-all.sh 产生的最新配置备份（仅搜索当前配置根的备份目录）
    elif [ -d "$BACKUP_DIR/configs" ]; then
        local newest
        newest=$(find "$BACKUP_DIR/configs" -name "openclaw.json.*" -type f -exec ls -t {} + 2>/dev/null | head -1 || echo "")
        if [ -n "$newest" ]; then
            backup_path="$newest"
            rollback_type="backup-all"
            info "找到最新 backup-all 备份：$backup_path"
        fi
    fi

    if [ -z "$backup_path" ]; then
        error "未找到任何备份，无法回滚"
    fi

    info "正在回滚..."
    warn "回滚将覆盖当前配置！"
    read -p "是否继续？[y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "已取消回滚"
        return 0
    fi
    
    # 回滚前先备份当前配置
    if [ -f "$OPENCLAW_CONFIG" ]; then
        cp "$OPENCLAW_CONFIG" "$BACKUP_DIR/pre_rollback_$TIMESTAMP.json"
        warn "已备份当前配置到：$BACKUP_DIR/pre_rollback_$TIMESTAMP.json"
    fi

    # 根据备份类型恢复
    if [ "$rollback_type" = "safe-update" ]; then
        # safe-update 备份是目录
        if [ -f "$backup_path/openclaw.json" ]; then
            cp "$backup_path/openclaw.json" "$OPENCLAW_CONFIG"
            success "已恢复 openclaw.json"
        fi
        if [ -d "$backup_path/configs" ]; then
            cp -r "$backup_path/configs" "$CLAWD_DIR/"
            success "已恢复 configs/"
        fi
        if [ -d "$backup_path/agents" ]; then
            cp -r "$backup_path/agents" "$CLAWD_DIR/"
            success "已恢复 agents/"
        fi
    else
        # backup-all 备份是单个文件
        cp "$backup_path" "$OPENCLAW_CONFIG"
        success "已恢复 openclaw.json（backup-all 格式）"
    fi

    # 验证配置
    if jq empty "$OPENCLAW_CONFIG" 2>/dev/null; then
        success "配置文件格式正确"
    else
        error "恢复的配置文件格式错误！请检查：$OPENCLAW_CONFIG"
    fi

    success "回滚完成！请重启 gateway: openclaw gateway restart"
}

# 显示帮助
show_help() {
    cat << EOF
御书房安全更新脚本

用法：$0 [选项]

选项：
  (无)        完整流程：备份 → 安全检查 → 更新
  --backup    仅备份配置
  --check     仅安全检查（8 项）
  --install-hook  安装 Git Hook 保护
  --rollback  回滚到上次备份
  --help      显示帮助

示例：
  $0                    # 完整更新流程
  $0 --backup           # 手动备份
  $0 --check            # 检查配置安全性
  $0 --install-hook     # 安装 Git Hook 保护
  $0 --rollback         # 出问题时回滚

EOF
}

# 主流程
main() {
    init_backup_dir
    
    case "${1:-}" in
        --backup)
            backup_configs
            ;;
        --check)
            safety_check
            ;;
        --install-hook)
            bash "$(dirname "$0")/pre-update-check.sh" --install-hook
            ;;
        --rollback)
            rollback
            ;;
        --help|-h)
            show_help
            ;;
        "")
            # 完整流程
            backup_configs
            echo ""
            safety_check
            echo ""
            read -p "是否继续更新？[y/N] " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                do_update
            else
                info "已取消更新"
            fi
            ;;
        *)
            error "未知选项：$1，使用 --help 查看帮助"
            ;;
    esac
}

main "$@"
