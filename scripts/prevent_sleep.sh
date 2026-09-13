#!/usr/bin/env bash
# ==============================================================================
# ThoughtEcho - 系统防休眠/保活守护脚本 (Keep-Alive Daemon)
#
# 作用：
# 1. 在云端环境（GitHub Codespaces / 容器 / 云主机）或本地系统中，
#    通过定期心跳、网络探活、文件 I/O 与终端微量活动，保持系统与环境活跃，
#    防止因长时间无输入而被宿主机或云平台判定为 Idle 超时挂起、休眠或自动关机。
# 2. 具备 X11/桌面防休眠兼容（xset/gsettings 若存在则自动关闭显示休眠）。
# 3. 单脚本自包含：支持后台守护运行 (start)、停止 (stop)、状态 (status)、前台 (run)。
#
# 用法：
#   ./scripts/prevent_sleep.sh start   # 后台启动保活守护进程
#   ./scripts/prevent_sleep.sh stop    # 停止保活守护进程
#   ./scripts/prevent_sleep.sh status  # 查看运行状态与心跳日志
#   ./scripts/prevent_sleep.sh run     # 前台运行（按 Ctrl+C 退出）
# ==============================================================================

set -euo pipefail

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
PID_FILE="/tmp/prevent_sleep.pid"
LOG_FILE="/tmp/prevent_sleep.log"
HEARTBEAT_FILE="/tmp/prevent_sleep.heartbeat"
INTERVAL_SECONDS=30

_log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo "$msg"
  echo "$msg" >> "$LOG_FILE"
}

_setup_desktop_inhibit() {
  # 若存在 X11 桌面环境，尝试关闭屏保与休眠
  if command -v xset >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
    xset s off -dpms >/dev/null 2>&1 || true
  fi

  # 若存在 gsettings 且有 session bus，尝试关闭休眠
  if command -v gsettings >/dev/null 2>&1 && [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' >/dev/null 2>&1 || true
  fi
}

_do_heartbeat() {
  local count=0
  _log "防休眠保活进程已就绪 (PID: $$, 间隔: ${INTERVAL_SECONDS}s)"
  _setup_desktop_inhibit

  while true; do
    count=$((count + 1))
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"

    # 1. 刷新心跳文件与时间戳 (触发文件系统活跃)
    echo "heartbeat: $ts, tick: $count, pid: $$" > "$HEARTBEAT_FILE"

    # 2. 轻量网络探活，防止连接超时或网络栈挂起
    if command -v curl >/dev/null 2>&1; then
      curl -s --connect-timeout 3 --max-time 5 "https://1.1.1.1" >/dev/null 2>&1 || true
    fi

    # 3. 产生微量文件系统活跃与日志保活
    touch "$LOG_FILE" 2>/dev/null || true

    # 每 100 次 (约 50 分钟) 压缩一次日志，防止无限增长
    if [ $((count % 100)) -eq 0 ]; then
      tail -n 200 "$LOG_FILE" > "${LOG_FILE}.tmp" 2>/dev/null && mv "${LOG_FILE}.tmp" "$LOG_FILE"
      _log "心跳正常运转中 (已累计运行 $count 次心跳)"
    fi

    sleep "$INTERVAL_SECONDS"
  done
}

start() {
  if [ -f "$PID_FILE" ]; then
    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      echo "防休眠保活守护进程已在运行中 (PID: $pid)。"
      return 0
    fi
  fi

  echo "正在启动防休眠保活守护进程..."
  if command -v setsid >/dev/null 2>&1; then
    setsid "$SCRIPT_PATH" run </dev/null >/dev/null 2>&1 &
  else
    nohup "$SCRIPT_PATH" run </dev/null >/dev/null 2>&1 &
  fi
  local new_pid=$!
  echo "$new_pid" > "$PID_FILE"
  sleep 1

  # 读取可能由 run() 更新的实际 PID
  if [ -f "$PID_FILE" ]; then
    new_pid="$(cat "$PID_FILE")"
  fi

  if kill -0 "$new_pid" 2>/dev/null; then
    echo "✅ 防休眠保活守护进程已成功在后台启动 (PID: $new_pid)。"
    echo "心跳间隔: ${INTERVAL_SECONDS} 秒，日志记录在 $LOG_FILE"
  else
    echo "❌ 启动失败，请检查日志: $LOG_FILE"
    return 1
  fi
}

stop() {
  if [ ! -f "$PID_FILE" ]; then
    echo "防休眠保活守护进程未运行 (PID 文件不存在)。"
    return 0
  fi

  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    echo "正在停止防休眠保活进程 (PID: $pid)..."
    kill "$pid" 2>/dev/null || true
    sleep 1
    if kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null || true
    fi
    echo "✅ 已成功停止。"
  else
    echo "进程已不存在。"
  fi
  rm -f "$PID_FILE" "$HEARTBEAT_FILE"
}

status() {
  if [ -f "$PID_FILE" ]; then
    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      echo "🟢 防休眠保活守护进程正在运行 (PID: $pid)"
      if [ -f "$HEARTBEAT_FILE" ]; then
        echo "最近心跳: $(cat "$HEARTBEAT_FILE")"
      fi
      echo "最近日志:"
      tail -n 10 "$LOG_FILE" 2>/dev/null || echo "暂无日志"
      return 0
    fi
  fi
  echo "⚪ 防休眠保活守护进程未在运行。"
  return 1
}

run() {
  echo $$ > "$PID_FILE"
  trap 'rm -f "$PID_FILE" "$HEARTBEAT_FILE"; exit 0' INT TERM
  trap '' HUP
  _do_heartbeat
}

case "${1:-}" in
  start)
    start
    ;;
  stop)
    stop
    ;;
  status)
    status
    ;;
  run)
    run
    ;;
  *)
    echo "用法: $0 {start|stop|status|run}"
    exit 1
    ;;
esac
