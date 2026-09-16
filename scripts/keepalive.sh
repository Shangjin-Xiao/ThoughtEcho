#!/usr/bin/env bash
# scripts/keepalive.sh - 防止容器/会话空闲休眠的心跳脚本
# 用法:
#   ./scripts/keepalive.sh &       # 后台启动
#   ./scripts/keepalive.sh stop    # 停止心跳

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || dirname "$SCRIPT_DIR")"
PID_FILE="$REPO_ROOT/.keepalive.pid"
LOG_FILE="$REPO_ROOT/.keepalive.log"

if [ "$1" = "stop" ]; then
  if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
      kill "$PID" 2>/dev/null
      echo "[keepalive] 已停止心跳守护进程 (PID: $PID)"
    else
      echo "[keepalive] 进程 $PID 已不存在"
    fi
    rm -f "$PID_FILE"
  else
    echo "[keepalive] 未找到 PID 文件"
  fi
  exit 0
fi

INTERVAL=${1:-60}
if ! [[ "$INTERVAL" =~ ^[1-9][0-9]*$ ]]; then
  echo "[keepalive] 错误: INTERVAL 必须是大于 0 的正整数: $INTERVAL" >&2
  exit 1
fi

if [ -f "$PID_FILE" ]; then
  OLD_PID=$(cat "$PID_FILE")
  if kill -0 "$OLD_PID" 2>/dev/null; then
    echo "[keepalive] 心跳守护进程已在运行中 (PID: $OLD_PID)"
    exit 0
  fi
fi

echo $$ > "$PID_FILE"

echo "[keepalive] 启动防止休眠心跳守护进程 (PID: $$, 间隔: ${INTERVAL}s)..." >> "$LOG_FILE"

trap 'rm -f "$PID_FILE"; echo "[keepalive] 心跳已终止" >> "$LOG_FILE"; exit 0' SIGINT SIGTERM

while true; do
  echo "[keepalive $(date '+%Y-%m-%d %H:%M:%S')] system active, heartbeat pulse" >> "$LOG_FILE"
  sleep "$INTERVAL"
done
