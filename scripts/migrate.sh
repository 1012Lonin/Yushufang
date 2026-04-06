#!/bin/bash
# ============================================
# 御书房 · 迁移脚本
#
# 功能：自动化服务器迁移（从旧服务器到新服务器）
# - 自动检测配置目录（~/.openclaw 或 ~/.clawdbot）
# - 备份所有关键数据
# - 传输到新服务器
# - 在新服务器恢复
#
# 用法（源服务器）：
#   bash scripts/migrate.sh --backup               # 生成迁移包
#   bash scripts/migrate.sh --backup --full       # 含工作区完整备份
#   bash scripts/migrate.sh --dry-run              # 预览备份内容
#
# 用法（新服务器）：
#   bash scripts/migrate.sh --restore <包路径>     # 从迁移包恢复
#   bash scripts/migrate.sh --restore <包路径> --dry-run
#
# 注意事项：
#   --backup 在源服务器执行
#   --restore 在新服务器执行
# ============================================

set -euo pipefail

# ---------- 颜色 ----------
RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[1;33m"
CYAN="\033[0;36m"; BLUE="\033[0;34m"; BOLD="\033[1m"; NC="\033[0m"

log()   { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $*"; }
ok()    { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
err()   { echo -e "${RED}[✗]${NC} $*" >&2; }

# ---------- 路径检测（备份模式下需要检测，restore 模式下可跳过）----------
# 【修复】restore 模式下无需检测已有配置，新服务器可能为空
detect_config_dir() {
    if [ -n "${CONFIG_DIR:-}" ]; then
      return 0  # operator override
    fi

    local openclaw_exists=0
    local clawdbot_exists=0
    [ -f "$HOME/.openclaw/openclaw.json" ] && openclaw_exists=1 || true
    [ -f "$HOME/.clawdbot/openclaw.json" ] && clawdbot_exists=1 || true

    if [ $openclaw_exists -eq 1 ] && [ $clawdbot_exists -eq 1 ]; then
      echo -e "${RED}✗ 错误：~/.openclaw 和 ~/.clawdbot 同时存在${NC}" >&2
      echo "  请明确指定：CONFIG_DIR=~/.openclaw 或 CONFIG_DIR=~/.clawdbot bash $0" >&2
      exit 1
    elif [ $openclaw_exists -eq 1 ]; then
      CONFIG_DIR="$HOME/.openclaw"
    elif [ $clawdbot_exists -eq 1 ]; then
      CONFIG_DIR="$HOME/.clawdbot"
    else
      echo -e "${RED}✗ 错误：未找到配置目录（~/.openclaw 或 ~/.clawdbot）${NC}" >&2
      exit 1
    fi
}

# ---------- 颜色 ----------
usage() {
    cat <<EOF
${BOLD}御书房 · 迁移脚本${NC}

${BOLD}用法（源服务器）：${NC}
  $(basename "$0") --backup               生成迁移包（含所有数据）
  $(basename "$0") --backup --full       含工作区完整备份
  $(basename "$0") --backup --dry-run     仅预览备份内容

${BOLD}用法（新服务器）：${NC}
  $(basename "$0") --restore <包路径>      从迁移包恢复
  $(basename "$0") --restore <pkg> --dry-run  仅预览恢复内容

${BOLD}环境变量：${NC}
  CONFIG_DIR     指定配置目录（覆盖自动检测）；restore 模式下默认 ~/.openclaw
  BACKUP_ROOT    指定备份根目录（默认 ~/yushufang-migration）

${BOLD}示例（新服务器恢复）：${NC}
  # 新服务器使用默认 ~/.openclaw 作为恢复目标
  bash scripts/migrate.sh --restore yushufang-migration-20260325_120000.tar.gz

  # 或明确指定恢复目标
  CONFIG_DIR=~/.clawdbot bash scripts/migrate.sh --restore <包路径>
EOF
    exit 0
}

# ---------- 参数解析 ----------
MODE=""
PKG_PATH=""
DRY_RUN=false
FULL_BACKUP=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --backup)   MODE="backup"; shift ;;
        --restore)  MODE="restore"; PKG_PATH="$2"; shift 2 ;;
        --dry-run)  DRY_RUN=true; shift ;;
        --full)     FULL_BACKUP=true; shift ;;
        -h|--help)  usage ;;
        *) err "未知选项: $1"; usage ;;
    esac
done

if [[ -z "$MODE" ]]; then
    err "请指定 --backup 或 --restore"
    usage
fi

# 初始化共享变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
MIGRATION_PKG="yushufang-migration-${TIMESTAMP}.tar.gz"

# 【修复】根据模式设置 CONFIG_DIR
# --backup 模式：需要检测已有配置
# --restore 模式：优先检测目标服务器已有配置（与备份端一致），无则默认 ~/.openclaw
if [[ "$MODE" == "backup" ]]; then
    BACKUP_ROOT="${BACKUP_ROOT:-$HOME/yushufang-migration}"
    detect_config_dir
else
    # restore 模式：自动检测目标服务器已有配置
    restore_openclaw=0
    restore_clawdbot=0
    [ -f "$HOME/.openclaw/openclaw.json" ] && restore_openclaw=1 || true
    [ -f "$HOME/.clawdbot/openclaw.json" ] && restore_clawdbot=1 || true

    if [ -n "${CONFIG_DIR:-}" ]; then
        : # 显式指定，保留原值
        log "使用显式配置目录：$CONFIG_DIR"
    elif [ $restore_openclaw -eq 1 ] && [ $restore_clawdbot -eq 1 ]; then
        echo -e "${RED}✗ 错误：目标服务器同时存在 ~/.openclaw 和 ~/.clawdbot${NC}" >&2
        echo "  请明确指定：CONFIG_DIR=~/.openclaw 或 CONFIG_DIR=~/.clawdbot bash $0 --restore ..." >&2
        exit 1
    elif [ $restore_clawdbot -eq 1 ]; then
        CONFIG_DIR="$HOME/.clawdbot"
        log "检测到目标使用 ~/.clawdbot"
    else
        CONFIG_DIR="$HOME/.openclaw"
        log "未检测到已有配置，默认使用 $CONFIG_DIR"
    fi
    echo -e "${CYAN}[i]${NC} 恢复目标配置目录：$CONFIG_DIR"
fi

# ============================================================
# 备份流程（源服务器）
# ============================================================

do_backup() {
    log "御书房迁移备份开始 — 配置目录：$CONFIG_DIR"
    echo ""

    mkdir -p "$BACKUP_ROOT"

    local stage_dir="$BACKUP_ROOT/staging.$TIMESTAMP"
    mkdir -p "$stage_dir"  # dry-run 仍需创建（供 migration-meta.txt 使用）

    local backed=0
    local skipped=0
    local backup_failures=0  # 记录失败数量，用于判断是否打印警告

    # ---- 检测制度 ----
    local regime="unknown"
    if command -v jq &>/dev/null && [[ -f "$CONFIG_DIR/openclaw.json" ]]; then
        regime=$(jq -r '._regime // "unknown"' "$CONFIG_DIR/openclaw.json" 2>/dev/null || echo "unknown")
    fi
    echo "detected_regime=$regime" > "$stage_dir/migration-meta.txt"
    [[ "$DRY_RUN" == "true" ]] && echo "  [dry-run] 制度: $regime" || true

    # ---- 1. 主配置文件 ----
    if [[ -f "$CONFIG_DIR/openclaw.json" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [dry-run] 备份 openclaw.json"
        else
            cp -p "$CONFIG_DIR/openclaw.json" "$stage_dir/openclaw.json"
            chmod 600 "$stage_dir/openclaw.json"
            ok "openclaw.json"
        fi
        ((++backed))
    else
        warn "openclaw.json 不存在，跳过"
        ((++skipped))
    fi

    # ---- 2. 记忆数据库 (SQLite) ----
    if [[ -d "$CONFIG_DIR/memory" ]]; then
        local mem_count
        mem_count=$(find "$CONFIG_DIR/memory" -name "*.sqlite" 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [dry-run] 备份 memory/ ($mem_count 个 .sqlite 文件)"
        else
            mkdir -p "$stage_dir/memory"
            local mem_failed=0
            for db in "$CONFIG_DIR/memory"/*.sqlite; do
                [[ -f "$db" ]] || continue
                if command -v sqlite3 &>/dev/null; then
                    local target="'$stage_dir/memory/$(basename "$db")'"
                    if sqlite3 "$db" ".backup $target" 2>/dev/null; then
                        : # sqlite3 .backup 成功
                    else
                        # 回退到 cp，但标记为失败
                        cp -p "$db" "$stage_dir/memory/" 2>/dev/null || mem_failed=1
                        mem_failed=1
                    fi
                else
                    cp -p "$db" "$stage_dir/memory/" 2>/dev/null || mem_failed=1
                fi
            done
            if [[ "$mem_failed" -eq 1 ]]; then
                warn "memory/ 部分数据库备份失败（SQLite 快照未完成）"
                backup_failures=$((backup_failures + 1))
            else
                ok "memory/ ($mem_count 个 SQLite 文件)"
            fi
        fi
        ((++backed))
    else
        warn "memory/ 目录不存在，跳过"
        ((++skipped))
    fi

    # ---- 3. Agent OAuth 凭据（Codex 修复）----
    # 备份所有 agents/*/agent/auth-profiles.json，保留目录结构
    if [[ -d "$CONFIG_DIR/agents" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [dry-run] 备份 agents/ (含 auth-profiles.json)"
        else
            mkdir -p "$stage_dir/agents"
            local agents_ok=true
            # 用 rsync 保留目录结构和隐藏文件
            if command -v rsync &>/dev/null; then
                rsync -a "$CONFIG_DIR/agents/" "$stage_dir/agents/" 2>/dev/null || agents_ok=false
            else
                # 回退：用 cp -a 保留隐藏文件
                cp -a "$CONFIG_DIR/agents/." "$stage_dir/agents/" 2>/dev/null || agents_ok=false
            fi
            if [[ "$agents_ok" == "true" ]]; then
                ok "agents/ (含 auth-profiles.json)"
            else
                warn "agents/ 部分文件备份失败，请手动检查"
                backup_failures=$((backup_failures + 1))
            fi
        fi
        [[ "$DRY_RUN" != "true" && "$agents_ok" == "true" ]] && ((++backed)) || true
    else
        warn "agents/ 目录不存在，跳过"
        ((++skipped))
    fi

    # ---- 4. 户部数据 ----
    local hubu_src="$HOME/clawd-hubu"
    if [[ -d "$hubu_src" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [dry-run] 备份 clawd-hubu/"
        else
            mkdir -p "$stage_dir/clawd-hubu"
            local hubu_ok=true
            # 用 rsync 保留隐藏文件
            if command -v rsync &>/dev/null; then
                rsync -a "$hubu_src/" "$stage_dir/clawd-hubu/" 2>/dev/null || hubu_ok=false
            else
                cp -a "$hubu_src/." "$stage_dir/clawd-hubu/" 2>/dev/null || hubu_ok=false
            fi
            if [[ "$hubu_ok" == "true" ]]; then
                ok "clawd-hubu/"
            else
                warn "clawd-hubu/ 部分文件备份失败，请手动检查"
                backup_failures=$((backup_failures + 1))
            fi
        fi
        [[ "$DRY_RUN" != "true" && "$hubu_ok" == "true" ]] && ((++backed)) || true
    else
        warn "clawd-hubu/ 不存在，跳过"
        ((++skipped))
    fi

    # ---- 5. .env 文件 ----
    if [[ -f "$HOME/.env" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [dry-run] 备份 .env"
        else
            cp -p "$HOME/.env" "$stage_dir/.env"
            chmod 600 "$stage_dir/.env"
            ok ".env"
        fi
        ((++backed))
    fi

    # ---- 6. 制度配置目录（按需）----
    if [[ -d "$CONFIG_DIR/configs" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [dry-run] 备份 configs/"
        else
            mkdir -p "$stage_dir/configs"
            local configs_ok=true
            cp -a "$CONFIG_DIR/configs/." "$stage_dir/configs/" 2>/dev/null || configs_ok=false
            if [[ "$configs_ok" == "true" ]]; then
                ok "configs/"
            else
                warn "configs/ 部分文件备份失败，请手动检查"
                backup_failures=$((backup_failures + 1))
            fi
        fi
        [[ "$DRY_RUN" != "true" && "$configs_ok" == "true" ]] && ((++backed)) || true
    fi

    # ---- 7. 工作区（--full 时）----
    if [[ "$FULL_BACKUP" == "true" ]]; then
        local clawd_src="$HOME/clawd"
        if [[ -d "$clawd_src" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                echo "  [dry-run] 备份 clawd/ (工作区，完整)"
            else
                mkdir -p "$stage_dir/clawd"
                # 关键：使用 rsync 或 cp -a 保留所有文件（含隐藏）
                local clawd_ok=true
                if command -v rsync &>/dev/null; then
                    rsync -a "$clawd_src/" "$stage_dir/clawd/" 2>/dev/null || clawd_ok=false
                else
                    cp -a "$clawd_src/." "$stage_dir/clawd/" 2>/dev/null || clawd_ok=false
                fi
                if [[ "$clawd_ok" == "true" ]]; then
                    ok "clawd/ (工作区完整备份)"
                else
                    warn "clawd/ 部分文件备份失败，请手动检查"
                    backup_failures=$((backup_failures + 1))
                fi
            fi
            [[ "$DRY_RUN" != "true" && "$clawd_ok" == "true" ]] && ((++backed)) || true
        else
            warn "clawd/ 不存在，跳过"
            ((++skipped))
        fi
    fi

    # ---- 8. Cron 任务记录 ----
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [dry-run] 备份 cron 任务"
    else
        if command -v openclaw &>/dev/null; then
            openclaw cron list > "$stage_dir/cron-list.txt" 2>/dev/null || true
        fi
        crontab -l > "$stage_dir/crontab.txt" 2>/dev/null || true
        ok "cron 任务"
    fi

    # ---- 打包 ----
    if [[ "$DRY_RUN" == "false" ]]; then
        echo ""
        log "打包迁移包..."

        # 写入元数据
        cat > "$stage_dir/migration-meta.txt" <<EOF
timestamp=$TIMESTAMP
config_dir=$CONFIG_DIR
regime=$regime
full_backup=$FULL_BACKUP
hostname=$(hostname)
EOF

        cd "$BACKUP_ROOT"
        tar -czf "$MIGRATION_PKG" "staging.$TIMESTAMP"
        chmod 600 "$MIGRATION_PKG"

        echo ""
        if [[ $backup_failures -gt 0 ]]; then
            echo -e "${YELLOW}[!]${NC} 警告：$backup_failures 个备份项存在部分失败，迁移包可能不完整"
            echo "  请在传输前检查备份内容：ls -la $BACKUP_ROOT/staging.$TIMESTAMP/"
            echo "  确认关键文件（openclaw.json、memory/*.sqlite、agents/）已正确备份"
            echo ""
        fi
        ok "迁移包已生成：$BACKUP_ROOT/$MIGRATION_PKG"
        echo "  大小：$(du -sh "$BACKUP_ROOT/$MIGRATION_PKG" | cut -f1)"
        echo ""
        echo "下一步：将迁移包传输到新服务器："
        echo "  scp $BACKUP_ROOT/$MIGRATION_PKG user@newserver:~/"
        echo ""
        echo "在新服务器运行："
        echo "  tar -xzf $MIGRATION_PKG"
        echo "  bash scripts/migrate.sh --restore staging.$TIMESTAMP"
        echo ""

        # 清理临时目录
        rm -rf "$stage_dir"
    fi

    echo ""
    echo "汇总：已备份=$backed 跳过=$skipped"
}

# ============================================================
# 恢复流程（新服务器）
# ============================================================

do_restore() {
    if [[ -z "$PKG_PATH" ]]; then
        err "请指定迁移包路径（--restore <路径>）"
        exit 1
    fi

    # 记录 Docker 是否被使用（用于恢复后重启对应容器）
    local docker_was_running=0

    # 支持目录（staging）或压缩包
    local src_dir=""
    local tmpdir=""  # 【修复】初始化，避免 set -u 下未声明变量导致清理崩溃
    if [[ -d "$PKG_PATH" ]]; then
        src_dir="$PKG_PATH"
    elif [[ -f "$PKG_PATH" ]]; then
        log "解压迁移包：$PKG_PATH"
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [dry-run] 解压到临时目录"
        else
            tmpdir=$(mktemp -d)
            tar -xzf "$PKG_PATH" -C "$tmpdir"
            # 找到解压出的 staging 目录
            src_dir=$(find "$tmpdir" -mindepth 1 -maxdepth 1 -type d | head -1)
            if [[ -z "$src_dir" ]]; then
                err "无法解压迁移包"
                exit 1
            fi
            echo "  已解压到：$src_dir"
        fi
    else
        err "迁移包不存在：$PKG_PATH"
        exit 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [dry-run] 从 $PKG_PATH 恢复"
        return 0
    fi

    log "御书房迁移恢复开始 — 配置目录：$CONFIG_DIR"
    echo ""

    # 读取元数据
    local meta_file="$src_dir/migration-meta.txt"
    local detected_regime="unknown"
    if [[ -f "$meta_file" ]]; then
        detected_regime=$(grep "^regime=" "$meta_file" 2>/dev/null | cut -d= -f2 || echo "unknown")
        echo "  来自服务器制度：$detected_regime"
    fi

    # ---- 0. 停止服务 ----
    echo ""
    warn "即将停止 Gateway..."
    if command -v openclaw &>/dev/null; then
        openclaw gateway stop 2>/dev/null || true
    fi
    if command -v docker &>/dev/null && docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qE "ai-court|yushufang"; then
        docker_was_running=1
        (cd "$PROJECT_ROOT" && docker compose down 2>/dev/null || true)
    fi
    ok "服务已停止"

    # ---- 1. 备份当前配置（安全回退）----
    echo ""
    log "备份当前配置..."
    mkdir -p "$CONFIG_DIR/.migration-pre-restore"
    if [[ -f "$CONFIG_DIR/openclaw.json" ]]; then
        cp -p "$CONFIG_DIR/openclaw.json" "$CONFIG_DIR/.migration-pre-restore/openclaw.json.$(date +%Y%m%d_%H%M%S)"
        ok "当前配置已备份"
    fi

    # ---- 2. 恢复 openclaw.json ----
    echo ""
    log "恢复主配置文件..."
    if [[ -f "$src_dir/openclaw.json" ]]; then
        cp -p "$src_dir/openclaw.json" "$CONFIG_DIR/openclaw.json"
        chmod 600 "$CONFIG_DIR/openclaw.json"
        # 验证 JSON 格式
        if command -v jq &>/dev/null && jq empty "$CONFIG_DIR/openclaw.json" 2>/dev/null; then
            ok "openclaw.json（JSON 格式正确）"
        else
            warn "openclaw.json 格式可能有问题，请检查"
        fi
    else
        warn "迁移包中无 openclaw.json，跳过"
    fi

    # ---- 3. 恢复记忆数据库 ----
    echo ""
    log "恢复记忆数据库..."
    mkdir -p "$CONFIG_DIR/memory"
    if [[ -d "$src_dir/memory" ]]; then
        for db in "$src_dir/memory"/*.sqlite; do
            [[ -f "$db" ]] || continue
            cp -p "$db" "$CONFIG_DIR/memory/"
            ok "$(basename "$db")"
        done
    else
        warn "迁移包中无 memory/ 目录"
    fi

    # ---- 4. 恢复 agents（含 auth-profiles.json）----
    echo ""
    log "恢复 Agent 目录（含 OAuth 凭据）..."
    if [[ -d "$src_dir/agents" ]]; then
        mkdir -p "$CONFIG_DIR/agents"
        if command -v rsync &>/dev/null; then
            rsync -a --delete "$src_dir/agents/" "$CONFIG_DIR/agents/"
        else
            # 先删除目标目录中的文件，再用 cp 复制（避免留下陈旧文件）
            find "$CONFIG_DIR/agents" -mindepth 1 -delete 2>/dev/null || true
            cp -a "$src_dir/agents/." "$CONFIG_DIR/agents/"
        fi
        ok "agents/ (含 auth-profiles.json)"
    else
        warn "迁移包中无 agents/ 目录"
    fi

    # ---- 5. 恢复 .env ----
    echo ""
    log "恢复 .env..."
    if [[ -f "$src_dir/.env" ]]; then
        cp -p "$src_dir/.env" "$HOME/.env"
        chmod 600 "$HOME/.env"
        ok ".env"
    else
        warn "迁移包中无 .env，跳过"
    fi

    # ---- 6. 恢复 configs（制度）----
    echo ""
    log "恢复 configs/（制度配置）..."
    if [[ -d "$src_dir/configs" ]]; then
        mkdir -p "$CONFIG_DIR/configs"
        if command -v rsync &>/dev/null; then
            rsync -a --delete "$src_dir/configs/" "$CONFIG_DIR/configs/"
        else
            find "$CONFIG_DIR/configs" -mindepth 1 -delete 2>/dev/null || true
            cp -a "$src_dir/configs/." "$CONFIG_DIR/configs/"
        fi
        ok "configs/"
    fi

    # ---- 7. 恢复 clawd-hubu ----
    echo ""
    log "恢复户部数据..."
    if [[ -d "$src_dir/clawd-hubu" ]]; then
        mkdir -p "$HOME/clawd-hubu"
        if command -v rsync &>/dev/null; then
            rsync -a --delete "$src_dir/clawd-hubu/" "$HOME/clawd-hubu/"
        else
            find "$HOME/clawd-hubu" -mindepth 1 -delete 2>/dev/null || true
            cp -a "$src_dir/clawd-hubu/." "$HOME/clawd-hubu/"
        fi
        ok "clawd-hubu/"
    else
        warn "迁移包中无 clawd-hubu/，跳过"
    fi

    # ---- 8. 恢复 clawd 工作区（--full 备份时）----
    echo ""
    log "恢复工作区..."
    if [[ -d "$src_dir/clawd" ]]; then
        mkdir -p "$HOME/clawd"
        if command -v rsync &>/dev/null; then
            rsync -a --delete "$src_dir/clawd/" "$HOME/clawd/"
        else
            find "$HOME/clawd" -mindepth 1 -delete 2>/dev/null || true
            cp -a "$src_dir/clawd/." "$HOME/clawd/"
        fi
        ok "clawd/ (工作区)"
    else
        warn "迁移包中无 clawd/（标准迁移不包含工作区，如需请用 --backup --full）"
    fi

    # ---- 9. 恢复 Cron 任务 ----
    echo ""
    log "恢复 Cron 任务..."
    if [[ -f "$src_dir/cron-list.txt" ]]; then
        echo "  原有 cron 任务（请在新服务器手动重新添加）："
        cat "$src_dir/cron-list.txt" | sed 's/^/    /'
        ok "cron-list.txt 已记录"
    fi
    if [[ -f "$src_dir/crontab.txt" ]] && [[ -s "$src_dir/crontab.txt" ]]; then
        echo "  系统 crontab 内容："
        cat "$src_dir/crontab.txt" | sed 's/^/    /'
        ok "crontab.txt 已记录"
    fi

    # ---- 10. 重新注入人设（如需要）----
    echo ""
    echo "  注意：人设已从迁移包中恢复，请确认人设版本符合预期。"
    echo "  如需使用当前仓库的模板人设覆盖，可手动运行："
    echo "    bash scripts/init-personas.sh $detected_regime"
    echo ""

    # ---- 11. 清理临时文件 ----
    if [[ -n "$tmpdir" ]] && [[ -d "$tmpdir" ]]; then
        rm -rf "$tmpdir"
    fi

    # ---- 12. 启动服务 ----
    echo ""
    log "启动服务..."
    if [[ "$docker_was_running" -eq 1 ]]; then
        (cd "$PROJECT_ROOT" && docker compose up -d 2>/dev/null || true)
        ok "Docker 容器已启动"
    elif command -v openclaw &>/dev/null; then
        openclaw gateway start 2>/dev/null || true
        ok "Gateway 已启动"
    fi

    echo ""
    ok "迁移恢复完成！"
    echo ""
    echo "下一步："
    echo "  1. 验证配置：openclaw status"
    echo "  2. 检查 cron 任务：openclaw cron list"
    echo "  3. Discord @mention 任一 Agent 确认响应"
    echo ""
    echo "如需回滚："
    echo "  cp $CONFIG_DIR/.migration-pre-restore/*.json $CONFIG_DIR/openclaw.json"
    if [[ "$docker_was_running" -eq 1 ]]; then
        echo "  (cd $PROJECT_ROOT && docker compose up -d)  # Docker 部署回滚"
    else
        echo "  openclaw gateway restart"
    fi
    echo ""
}

# ============================================================
# 主入口
# ============================================================

case "$MODE" in
    backup)
        do_backup
        ;;
    restore)
        do_restore
        ;;
esac
