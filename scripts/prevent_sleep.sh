#!/usr/bin/env bash
# ==============================================================================
# ThoughtEcho - 系统防休眠/保活守护脚本 (Keep-Alive Daemon)
#
# 作用：
# 1. 在云端环境（GitHub Codespaces / 容器 / 云主机）或本地系统中，
#    通过定期心跳、网络探活、文件 I/O 与终端微量活动，保持系统与环境活跃，
#    防止因长时间无输入而被宿主机或云平台判定为 Idle 超时挂起、休眠或自动关机。
# 2. 具备 X11/桌面防休眠兼容（xset/gsettings 若存在则自动关闭显示休眠，退出时恢复）。
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
HEARTBEAT_URL="${HEARTBEAT_URL:-}"
PREV_GSETTINGS_SLEEP=""

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

  # 若存在 gsettings 且有 session bus，记录原配置并尝试关闭休眠
  if command -v gsettings >/dev/null 2>&1 && [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    PREV_GSETTINGS_SLEEP="$(gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 2>/dev/null || true)"
    if [ -n "$PREV_GSETTINGS_SLEEP" ]; then
      echo "$PREV_GSETTINGS_SLEEP" > "/tmp/prevent_sleep.prev_gsettings" 2>/dev/null || true
    fi
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' >/dev/null 2>&1 || true
  fi
}

_restore_desktop_inhibit() {
  local prev="${PREV_GSETTINGS_SLEEP:-}"
  if [ -z "$prev" ] && [ -f "/tmp/prevent_sleep.prev_gsettings" ]; then
    prev="$(cat "/tmp/prevent_sleep.prev_gsettings" 2>/dev/null || true)"
  fi
  if [ -n "$prev" ] && command -v gsettings >/dev/null 2>&1 && [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    local orig="${prev//\'/}"
    if [ -n "$orig" ]; then
      gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type "$orig" >/dev/null 2>&1 || true
    fi
  fi
  rm -f "/tmp/prevent_sleep.prev_gsettings" 2>/dev/null || true
  if command -v xset >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
    xset s on +dpms >/dev/null 2>&1 || true
  fi
}

_is_running() {
  local pid="$1"
  if [ -z "$pid" ]; then
    return 1
  fi
  if ! kill -0 "$pid" 2>/dev/null; then
    return 1
  fi
  # 验证进程命令行，防止 PID 复用误判
  if command -v ps >/dev/null 2>&1; then
    local args
    args="$(ps -p "$pid" -o args= 2>/dev/null || true)"
    if echo "$args" | grep -q "prevent_sleep.sh run"; then
      return 0
    fi
    return 1
  fi
  return 0
}

_sleep_pid=""

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

    # 2. 轻量探活，防止连接超时或网络栈挂起
    if [ -n "${HEARTBEAT_URL:-}" ]; then
      if command -v curl >/dev/null 2>&1; then
        curl -s --connect-timeout 3 --max-time 5 "$HEARTBEAT_URL" >/dev/null 2>&1 || true
      fi
    else
      # 默认本地探活，无外部网络依赖
      if [ -r /proc/net/dev ]; then
        head -n 2 /proc/net/dev >/dev/null 2>&1 || true
      elif command -v ifconfig >/dev/null 2>&1; then
        ifconfig -a >/dev/null 2>&1 || true
      elif command -v ip >/dev/null 2>&1; then
        ip addr >/dev/null 2>&1 || true
      fi
    fi

    # 3. 产生微量文件系统活跃与日志保活
    touch "$LOG_FILE" 2>/dev/null || true

    # 每 100 次 (约 50 分钟) 压缩一次日志，防止无限增长
    if [ $((count % 100)) -eq 0 ]; then
      tail -n 200 "$LOG_FILE" > "${LOG_FILE}.tmp" 2>/dev/null && mv "${LOG_FILE}.tmp" "$LOG_FILE"
      _log "心跳正常运转中 (已累计运行 $count 次心跳)"
    fi

    # 使用可被信号即时中断的后台等待
    sleep "$INTERVAL_SECONDS" &
    _sleep_pid=$!
    wait "$_sleep_pid" 2>/dev/null || true
    _sleep_pid=""
  done
}

start() {
  if [ -f "$PID_FILE" ]; then
    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [ -n "$pid" ] && _is_running "$pid"; then
      echo "防休眠保活守护进程已在运行中 (PID: $pid)。"
      return 0
    fi
  fi

  echo "正在启动防休眠保活守护进程..."
  rm -f "$PID_FILE"
  if command -v setsid >/dev/null 2>&1; then
    setsid "$SCRIPT_PATH" run </dev/null >/dev/null 2>&1 &
  else
    nohup "$SCRIPT_PATH" run </dev/null >/dev/null 2>&1 &
  fi
  local bg_pid=$!

  # 等待后台守护进程自身就绪并写入真实 PID
  local wait_count=0
  local new_pid=""
  while [ $wait_count -lt 20 ]; do
    if [ -s "$PID_FILE" ]; then
      new_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
      if [ -n "$new_pid" ] && _is_running "$new_pid"; then
        break
      fi
    fi
    sleep 0.1
    wait_count=$((wait_count + 1))
  done

  if [ -z "$new_pid" ]; then
    new_pid="$bg_pid"
    echo "$new_pid" > "$PID_FILE"
  fi

  if _is_running "$new_pid"; then
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
  if [ -n "$pid" ] && _is_running "$pid"; then
    echo "正在停止防休眠保活进程 (PID: $pid)..."
    kill "$pid" 2>/dev/null || true
    local wait_count=0
    while _is_running "$pid" && [ $wait_count -lt 10 ]; do
      sleep 0.2
      wait_count=$((wait_count + 1))
    done
    if _is_running "$pid"; then
      kill -9 "$pid" 2>/dev/null || true
      sleep 0.2
    fi
    echo "✅ 已成功停止。"
  else
    echo "进程已不存在或 PID 已被复用。"
  fi
  _restore_desktop_inhibit
  rm -f "$PID_FILE" "$HEARTBEAT_FILE"
}

status() {
  if [ -f "$PID_FILE" ]; then
    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [ -n "$pid" ] && _is_running "$pid"; then
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

_cleaned_up=0
_cleanup() {
  if [ "$_cleaned_up" -eq 1 ]; then
    return 0
  fi
  _cleaned_up=1
  if [ -n "${_sleep_pid:-}" ]; then
    kill "$_sleep_pid" 2>/dev/null || true
  fi
  _restore_desktop_inhibit
  rm -f "$PID_FILE" "$HEARTBEAT_FILE" "/tmp/prevent_sleep.prev_gsettings"
}

run() {
  echo $$ > "$PID_FILE"
  trap '_cleanup; exit 0' INT TERM
  trap '_cleanup' EXIT
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
