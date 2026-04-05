#!/usr/bin/env python3
"""
hubu_data_collect.py — 户部用量数据收集与阈值检查模块

每 30 分钟由系统 cron 运行，不调用 LLM。
读取阈值优先级：环境变量 > thresholds.json > 代码硬编码默认值。

数据文件（均存于 $HOME/clawd-hubu/data/）：
  - ticks/YYYY-MM-DD.jsonl        每 30 分钟追加一行
  - daily-snapshots/YYYY-MM-DD.json  每日汇总（0点生成）
  - weekly-snapshots/YYYY-WXX.json   每周汇总（周一 0点生成）
  - rolling/rolling-window.json     当前 5 小时滚动窗口状态
  - api-usage.json                 最新快照（向后兼容）
  - thresholds.json                  阈值配置（用户可编辑）
  - alerts/cooldown.json             告警冷却状态

阈值（默认，月限额 5,000,000）：
  5h滚动窗口  Soft: 80,000   Hard: 120,000
  日用量      Soft: 120,000  Hard: 166,667
  周配额      Soft: 800,000  Hard: 1,000,000
  月配额      Soft: 3,500,000 (70%)  Hard: 4,500,000 (90%)
"""

import json
import os
import sys
import argparse
from datetime import datetime, timezone, timedelta
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import URLError

# ─── 路径配置 ───────────────────────────────────────────────────────────────────

HOME = os.environ.get("HOME", "/home/ubuntu")
DATA_DIR = Path(os.environ.get("HUBU_DATA_DIR", f"{HOME}/clawd-hubu/data"))
STATE_DIR = Path(os.environ.get("OPENCLAW_STATE_DIR", f"{HOME}/.openclaw"))
AGENTS_DIR = STATE_DIR / "agents"
DISCORD_CHANNEL = os.environ.get("HUBU_DISCORD_CHANNEL", "YOUR_CHANNEL_ID")
DISCORD_ACCOUNT = os.environ.get("HUBU_DISCORD_ACCOUNT", "silijian")
AUTH_TOKEN = os.environ.get("BOLUO_AUTH_TOKEN", "")
GUI_URL = os.environ.get("HUBU_GUI_URL", "http://localhost:18795")

# ─── 部门映射 ───────────────────────────────────────────────────────────────────

AGENT_DEPT_MAP = {
    "silijian": "司礼监",
    "gongbu": "工部",
    "hubu": "户部",
    "libu": "礼部",
    "libu2": "吏部",
    "xingbu": "刑部",
    "bingbu": "兵部",
    "neige": "内阁",
    "duchayuan": "都察院",
    "neiwufu": "内务府",
    "hanlinyuan": "翰林院",
    "hanlin_zhang": "翰林院·掌院学士",
    "hanlin_xiuzhuan": "翰林院·修撰",
    "hanlin_bianxiu": "翰林院·编修",
    "hanlin_jiantao": "翰林院·检讨",
    "hanlin_shujishi": "翰林院·庶吉士",
    "taiyiyuan": "太医院",
    "guozijian": "国子监",
    "yushanfang": "御膳房",
}
if os.environ.get("HUBU_DEPT_MAP"):
    AGENT_DEPT_MAP = json.loads(os.environ["HUBU_DEPT_MAP"])

# ─── 阈值（优先级：环境变量 > thresholds.json > 默认值）───────────────────────────

DEFAULTS = {
    "MONTHLY_LIMIT": 5_000_000,
    "MONTHLY_SOFT": 3_500_000,     # 70%
    "MONTHLY_HARD": 4_500_000,     # 90%
    "WEEKLY_LIMIT": 5_000_000,
    "WEEKLY_SOFT": 800_000,
    "WEEKLY_HARD": 1_000_000,
    "DAILY_LIMIT": 5_000_000,
    "DAILY_SOFT": 120_000,
    "DAILY_HARD": 166_667,
    "ROLLING_WINDOW_HOURS": 5,
    "ROLLING_SOFT": 80_000,
    "ROLLING_HARD": 120_000,
    "ALERT_COOLDOWN_HOURS": 4,
    "TOKEN_PRICE_PER_M": 0.3,
}


def load_thresholds() -> dict:
    """加载阈值，优先级：环境变量 > thresholds.json > DEFAULTS"""
    t = dict(DEFAULTS)
    # 从 thresholds.json 读取（文件优先于硬编码默认值）
    thresholds_file = DATA_DIR / "thresholds.json"
    if thresholds_file.exists():
        try:
            t.update(json.loads(thresholds_file.read_text()))
        except (json.JSONDecodeError, OSError):
            pass
    # 环境变量永远覆盖
    for key in DEFAULTS:
        env_key = f"HUBU_{key}"
        if env_key in os.environ:
            try:
                t[key] = int(os.environ[env_key])
            except ValueError:
                pass
    return t


def ensure_dirs():
    """确保所有必要的目录存在"""
    for sub in ("ticks", "daily-snapshots", "weekly-snapshots",
                "rolling", "alerts"):
        (DATA_DIR / sub).mkdir(parents=True, exist_ok=True)


# ─── 数据获取 ───────────────────────────────────────────────────────────────────

def fetch_total_tokens() -> int:
    """从 GUI API 获取当前 billing period 累计 token 总数"""
    if not AUTH_TOKEN:
        log("WARNING: BOLUO_AUTH_TOKEN not set, totalTokens=0")
        return 0
    req = Request(
        f"{GUI_URL}/api/tokens",
        headers={"Authorization": f"Bearer {AUTH_TOKEN}"},
    )
    try:
        with urlopen(req, timeout=10) as r:
            data = json.loads(r.read())
            return int(data.get("totalTokens", 0))
    except (URLError, json.JSONDecodeError, ValueError) as e:
        log(f"WARNING: failed to fetch /api/tokens: {e}")
        return 0


def fetch_dept_tokens() -> dict:
    """从各 agent sessions.json 推算部门用量（估算）"""
    by_dept = {}
    if not AGENTS_DIR.exists():
        return by_dept
    for agent_dir in AGENTS_DIR.iterdir():
        if not agent_dir.is_dir():
            continue
        sessions_path = agent_dir / "sessions" / "sessions.json"
        if not sessions_path.exists():
            continue
        try:
            sessions = json.load(sessions_path.open())
            dept_tokens = sum(
                (s.get("inputTokens", 0) + s.get("outputTokens", 0))
                for s in sessions.values() if isinstance(s, dict)
            )
            dept_name = AGENT_DEPT_MAP.get(agent_dir.name, agent_dir.name)
            by_dept[dept_name] = dept_tokens
        except (json.JSONDecodeError, OSError):
            pass
    return by_dept


# ─── 时间工具 ─────────────────────────────────────────────────────────────────

TZ = timezone(timedelta(hours=8))  # 北京时间


def now() -> datetime:
    return datetime.now(TZ)


def today_str() -> str:
    return now().strftime("%Y-%m-%d")


def iso_week() -> str:
    """返回 'YYYY-WXX' 格式的 ISO 周编号"""
    cal = now().isocalendar()
    return f"{cal[0]}-W{cal[1]:02d}"


def prev_day_str() -> str:
    return (now() - timedelta(days=1)).strftime("%Y-%m-%d")


# ─── 滚动窗口 ─────────────────────────────────────────────────────────────────

def compute_rolling_window(tokens_now: int) -> dict:
    """
    计算 5 小时滚动窗口用量。
    窗口内第一条记录 totalTokens 到当前 totalTokens 的差值。
    不足两条记录时返回 windowTokens=null。
    """
    window_hours = int(os.environ.get("HUBU_ROLLING_WINDOW_HOURS", "5"))
    tick_file = DATA_DIR / "ticks" / f"{today_str()}.jsonl"
    entries = []

    if tick_file.exists():
        cutoff = now() - timedelta(hours=6)  # 多读 1 小时作为缓冲
        with tick_file.open() as f:
            for line in f:
                try:
                    rec = json.loads(line)
                    rec_ts = datetime.fromisoformat(rec["ts"]).astimezone(TZ)
                    if rec_ts >= cutoff:
                        entries.append(rec)
                except (json.JSONDecodeError, KeyError, ValueError):
                    continue

    # 加入当前记录作为最新
    entries.append({"ts": now().isoformat(), "totalTokens": tokens_now})

    # 过滤到精确的 window_hours 窗口
    cutoff_window = now() - timedelta(hours=window_hours)
    in_window = sorted(
        [e for e in entries if datetime.fromisoformat(e["ts"]).astimezone(TZ) >= cutoff_window],
        key=lambda e: e["ts"],
    )

    if len(in_window) < 2:
        return {"windowTokens": None, "windowHours": window_hours, "entries": [], "computedAt": now().isoformat()}

    window_tokens = in_window[-1]["totalTokens"] - in_window[0]["totalTokens"]
    return {
        "windowTokens": window_tokens,
        "windowHours": window_hours,
        "entries": in_window,
        "computedAt": now().isoformat(),
    }


# ─── 告警冷却 ─────────────────────────────────────────────────────────────────

COOLDOWN_FILE = DATA_DIR / "alerts" / "cooldown.json"


def is_in_cooldown(alert_key: str, cooldown_hours: int) -> bool:
    if not COOLDOWN_FILE.exists():
        return False
    try:
        cooldown = json.loads(COOLDOWN_FILE.read_text())
    except (json.JSONDecodeError, OSError):
        return False
    last_fired = cooldown.get(alert_key)
    if not last_fired:
        return False
    last_dt = datetime.fromisoformat(last_fired).astimezone(TZ)
    return now() - last_dt < timedelta(hours=cooldown_hours)


def record_alert_fired(alert_key: str):
    cooldown = {}
    if COOLDOWN_FILE.exists():
        try:
            cooldown = json.loads(COOLDOWN_FILE.read_text())
        except (json.JSONDecodeError, OSError):
            pass
    cooldown[alert_key] = now().isoformat()
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    (DATA_DIR / "alerts").mkdir(exist_ok=True)
    COOLDOWN_FILE.write_text(json.dumps(cooldown))


# ─── Discord 告警 ─────────────────────────────────────────────────────────────

def send_discord_alert(message: str):
    import subprocess
    cmd = [
        "openclaw", "message", "send",
        "--channel", "discord",
        "--account", DISCORD_ACCOUNT,
        "--target", DISCORD_CHANNEL,
        "--message", message,
    ]
    try:
        subprocess.run(cmd, capture_output=True, timeout=15)
    except (subprocess.TimeoutExpired, FileNotFoundError):
        log(f"WARNING: failed to send Discord alert: {message[:80]}")


# ─── 日志 ─────────────────────────────────────────────────────────────────────

def log(msg: str):
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    with (DATA_DIR / "collect.log").open("a") as f:
        f.write(f"{now().isoformat()} {msg}\n")


# ─── 快照构建 ─────────────────────────────────────────────────────────────────

def build_daily_snapshot(date: str, total_tokens: int, daily_delta: int,
                        monthly_progress: float, week: str, week_total: int,
                        rolling_tokens: int, by_dept: dict) -> dict:
    """构建每日汇总快照"""
    tick_file = DATA_DIR / "ticks" / f"{date}.jsonl"
    peak_rate = 0
    if tick_file.exists():
        prev_tokens = None
        with tick_file.open() as f:
            for line in f:
                try:
                    rec = json.loads(line)
                    t = rec.get("totalTokens", 0)
                    if prev_tokens is not None:
                        rate = t - prev_tokens
                        if rate > peak_rate:
                            peak_rate = rate
                    prev_tokens = t
                except (json.JSONDecodeError, KeyError):
                    pass

    return {
        "date": date,
        "totalTokens": total_tokens,
        "dailyTokens": daily_delta,
        "monthlyProgress": round(monthly_progress, 2),
        "weekNumber": week,
        "weekTokens": week_total,
        "rollingWindowTokens": rolling_tokens or 0,
        "byDept": by_dept,
        "tickCount": peak_rate,
    }


def build_weekly_snapshot(week: str, total_tokens: int, daily_tokens_list: list,
                          monthly_progress: float, by_dept: dict) -> dict:
    daily_avg = round(sum(daily_tokens_list) / len(daily_tokens_list)) if daily_tokens_list else 0
    trend = "stable"
    if len(daily_tokens_list) >= 3:
        if daily_tokens_list[-1] > daily_tokens_list[-3] * 1.1:
            trend = "rising"
        elif daily_tokens_list[-1] < daily_tokens_list[-3] * 0.9:
            trend = "falling"
    return {
        "week": week,
        "totalTokens": total_tokens,
        "dailyAvg": daily_avg,
        "dailyTokens": daily_tokens_list,
        "monthlyProgress": round(monthly_progress, 2),
        "trend": trend,
        "byDept": by_dept,
    }


# ─── 阈值检查 ─────────────────────────────────────────────────────────────────

def check_thresholds(rolling_tokens: int | None, daily_delta: int, week_total: int,
                    monthly_tokens: int, thresholds: dict, by_dept: dict):
    """评估所有阈值层级，触发告警"""
    cooldown_hours = thresholds["ALERT_COOLDOWN_HOURS"]
    results = []

    # 5h 滚动窗口
    if rolling_tokens is not None:
        if rolling_tokens > thresholds["ROLLING_HARD"]:
            key = "ROLLING_HARD"
            if not is_in_cooldown(key, cooldown_hours):
                send_discord_alert(
                    f":rotating_light: **户部紧急 — 5小时滚动窗口超限**\n"
                    f"当前窗口: {rolling_tokens:,} / {thresholds['ROLLING_HARD']:,} tokens\n"
                    f"建议立即审查最近 5 小时内的 API 调用任务。"
                )
                record_alert_fired(key)
                results.append(f"ROLLING_HARD:{rolling_tokens:,}")
        elif rolling_tokens > thresholds["ROLLING_SOFT"]:
            key = "ROLLING_SOFT"
            if not is_in_cooldown(key, cooldown_hours):
                results.append(f"ROLLING_SOFT:{rolling_tokens:,}")
                record_alert_fired(key)

    # 日用量
    if daily_delta > thresholds["DAILY_HARD"]:
        key = "DAILY_HARD"
        if not is_in_cooldown(key, cooldown_hours):
            send_discord_alert(
                f":warning: **户部告警 — 日用量超限**\n"
                f"今日累计: {daily_delta:,} / {thresholds['DAILY_HARD']:,} tokens\n"
                f"建议 @司礼监 审查今日任务。"
            )
            record_alert_fired(key)
            results.append(f"DAILY_HARD:{daily_delta:,}")
    elif daily_delta > thresholds["DAILY_SOFT"]:
        key = "DAILY_SOFT"
        if not is_in_cooldown(key, cooldown_hours):
            results.append(f"DAILY_SOFT:{daily_delta:,}")
            record_alert_fired(key)

    # 周配额
    if week_total > thresholds["WEEKLY_HARD"]:
        key = "WEEKLY_HARD"
        if not is_in_cooldown(key, cooldown_hours):
            send_discord_alert(
                f":chart_with_downwards_trend: **户部告警 — 本周配额超限**\n"
                f"本周累计: {week_total:,} / {thresholds['WEEKLY_HARD']:,} tokens\n"
                f"建议审阅本周用量构成。"
            )
            record_alert_fired(key)
            results.append(f"WEEKLY_HARD:{week_total:,}")
    elif week_total > thresholds["WEEKLY_SOFT"]:
        key = "WEEKLY_SOFT"
        if not is_in_cooldown(key, cooldown_hours):
            results.append(f"WEEKLY_SOFT:{week_total:,}")
            record_alert_fired(key)

    # 月配额
    if monthly_tokens > thresholds["MONTHLY_HARD"]:
        key = "MONTHLY_HARD"
        if not is_in_cooldown(key, cooldown_hours):
            remaining = thresholds["MONTHLY_LIMIT"] - monthly_tokens
            days_in_month = 30
            days_remaining = max(1, days_in_month - now().day)
            daily_allowance = remaining // max(1, days_remaining)
            send_discord_alert(
                f":fire: **户部紧急 — 本月配额已达 90%！**\n"
                f"本月累计: {monthly_tokens:,} / {thresholds['MONTHLY_LIMIT']:,} "
                f"tokens ({round(monthly_tokens/thresholds['MONTHLY_LIMIT']*100,1)}%)\n"
                f"剩余: {remaining:,} tokens | 剩余天数: {days_remaining} | "
                f"日均可用: {daily_allowance:,}\n"
                f"建议 @司礼监 立即节制用量或追加预算！"
            )
            record_alert_fired(key)
            results.append(f"MONTHLY_HARD:{round(monthly_tokens/thresholds['MONTHLY_LIMIT']*100,1)}%")
    elif monthly_tokens > thresholds["MONTHLY_SOFT"]:
        key = "MONTHLY_SOFT"
        if not is_in_cooldown(key, cooldown_hours):
            results.append(f"MONTHLY_SOFT:{round(monthly_tokens/thresholds['MONTHLY_LIMIT']*100,1)}%")
            record_alert_fired(key)

    return results


# ─── 主程序 ─────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="户部用量数据收集与阈值检查")
    parser.add_argument("--dry-run", action="store_true", help="不写入文件也不发告警")
    args = parser.parse_args()

    ensure_dirs()
    thresholds = load_thresholds()
    now_ts = now()

    # 获取数据
    total_tokens = fetch_total_tokens()
    by_dept = fetch_dept_tokens()

    # 滚动窗口
    rolling = compute_rolling_window(total_tokens)
    rolling_tokens = rolling.get("windowTokens")

    # 月进度
    monthly_tokens = total_tokens
    monthly_progress = (monthly_tokens / thresholds["MONTHLY_LIMIT"]) * 100

    # 日增量
    prev_day = prev_day_str()
    prev_snapshot_path = DATA_DIR / "daily-snapshots" / f"{prev_day}.json"
    if prev_snapshot_path.exists():
        try:
            prev_total = json.loads(prev_snapshot_path.read_text()).get("totalTokens", 0)
        except (json.JSONDecodeError, OSError):
            prev_total = 0
    else:
        prev_total = 0
    daily_delta = total_tokens - prev_total

    # 周增量
    prev_week_path = DATA_DIR / "weekly-snapshots" / f"{iso_week()}.json"
    if prev_week_path.exists():
        try:
            week_total = json.loads(prev_week_path.read_text()).get("totalTokens", 0)
        except (json.JSONDecodeError, OSError):
            week_total = total_tokens
    else:
        week_total = total_tokens

    # ── 写最新快照（向后兼容）───────────────────────────────────────────────────
    snapshot = {
        "totalTokens": total_tokens,
        "monthlyProgress": round(monthly_progress, 2),
        "dailyTokens": daily_delta,
        "weekNumber": iso_week(),
        "weekTokens": week_total,
        "rollingWindowTokens": rolling_tokens,
        "byDept": by_dept,
        "ts": now_ts.isoformat(),
    }
    (DATA_DIR / "api-usage.json").write_text(
        json.dumps(snapshot, indent=2, ensure_ascii=False)
    )

    # ── 写滚动窗口状态─────────────────────────────────────────────────────────
    (DATA_DIR / "rolling" / "rolling-window.json").write_text(
        json.dumps(rolling, indent=2, ensure_ascii=False)
    )

    # ── 追加 tick─────────────────────────────────────────────────────────────
    tick_file = DATA_DIR / "ticks" / f"{today_str()}.jsonl"
    tick_line = {
        "ts": now_ts.isoformat(),
        "totalTokens": total_tokens,
        "dailyTokens": daily_delta,
        "monthlyProgress": round(monthly_progress, 2),
        "weekTokens": week_total,
        "rollingWindowTokens": rolling_tokens,
        "byDept": by_dept,
    }
    with tick_file.open("a") as f:
        f.write(json.dumps(tick_line, ensure_ascii=False) + "\n")

    # ── 检查阈值─────────────────────────────────────────────────────────────
    if not args.dry_run:
        alert_results = check_thresholds(
            rolling_tokens, daily_delta, week_total,
            monthly_tokens, thresholds, by_dept,
        )
    else:
        alert_results = []

    # ── 每日 0 点：生成当日快照文件────────────────────────────────────────────
    # 如果今日快照尚不存在（今日第一条记录），则创建占位快照
    today_snap_path = DATA_DIR / "daily-snapshots" / f"{today_str()}.json"
    if not today_snap_path.exists():
        today_snap = build_daily_snapshot(
            today_str(), total_tokens, daily_delta,
            monthly_progress, iso_week(), week_total,
            rolling_tokens or 0, by_dept,
        )
        today_snap_path.write_text(json.dumps(today_snap, indent=2, ensure_ascii=False))

    # ── 周一 0 点：生成周快照────────────────────────────────────────────────
    # 检测 ISO 周是否切换（新周开始时生成上周快照）
    week_file = DATA_DIR / "weekly-snapshots" / f"{iso_week()}.json"
    if not week_file.exists():
        # 取过去 7 天的每日快照构建周数据
        daily_files = sorted(DATA_DIR / "daily-snapshots".glob("*.json"))[-7:]
        daily_tokens_list = []
        for f in daily_files:
            try:
                daily_tokens_list.append(json.loads(f.read_text()).get("dailyTokens", 0))
            except (json.JSONDecodeError, OSError):
                pass
        week_snap = build_weekly_snapshot(
            iso_week(), total_tokens, daily_tokens_list,
            monthly_progress, by_dept,
        )
        week_file.write_text(json.dumps(week_snap, indent=2, ensure_ascii=False))

    # ── 日志──────────────────────────────────────────────────────────────────
    log(f"total={total_tokens:,} rolling={rolling_tokens} daily={daily_delta:,} "
        f"weekly={week_total:,} month={monthly_progress:.1f}% "
        f"alerts={alert_results}")

    print(
        f"[hubu] total={total_tokens:,} rolling={rolling_tokens} "
        f"daily={daily_delta:,} weekly={week_total:,} "
        f"month={monthly_progress:.1f}% alerts={alert_results}"
    )


if __name__ == "__main__":
    main()
