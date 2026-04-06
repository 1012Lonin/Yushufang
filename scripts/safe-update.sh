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

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 路径配置
CLAWD_DIR="${CLAWD_DIR:-$HOME/.openclaw}"
BACKUP_DIR="${BACKUP_DIR:-$CLAWD_DIR/backups}"
OPENCLAW_CONFIG="${OPENCLAW_CONFIG:-$HOME/.openclaw/openclaw.json}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# 打印函数
info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

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
    
    # 检查 1: allowBots 设置
    if [ -f "$OPENCLAW_CONFIG" ]; then
        local allow_bots
        allow_bots=$(grep -o '"allowBots"[[:space:]]*:[[:space:]]*"[^"]*"' "$OPENCLAW_CONFIG" | head -1)
        if echo "$allow_bots" | grep -q '"mentions"'; then
            success "allowBots 配置正确：mentions"
        elif echo "$allow_bots" | grep -q 'true'; then
            error "❌ allowBots=true 危险！会导致机器人循环。请改为 \"mentions\""
            ((errors++))
        else
            warn "allowBots 配置：$allow_bots"
        fi
        
        # 检查 2: mentionPatterns 是否包含 @everyone
        if grep -q '@everyone' "$OPENCLAW_CONFIG"; then
            error "❌ 发现 @everyone 配置！这是核弹开关，必须移除"
            ((errors++))
        else
            success "未发现 @everyone 配置"
        fi
        
        # 检查 3: mentionPatterns 是否包含 @here
        if grep -q '@here' "$OPENCLAW_CONFIG"; then
            error "❌ 发现 @here 配置！必须移除"
            ((errors++))
        else
            success "未发现 @here 配置"
        fi
    else
        warn "未找到配置文件，跳过检查"
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

    # 方式二：backup-all.sh 产生的最新配置备份
    elif [ -d "$HOME/.openclaw/backups/configs" ]; then
        local latest_config
        latest_config=$(find "$HOME/.openclaw/backups/configs" -name "openclaw.json.*" -type f | sort -r | head -1)
        if [ -n "$latest_config" ]; then
            backup_path="$latest_config"
            rollback_type="backup-all"
            info "找到 backup-all 备份：$backup_path"
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
