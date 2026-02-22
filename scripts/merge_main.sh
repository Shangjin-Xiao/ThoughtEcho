#!/bin/bash
# 拉取远程 main 并合并到当前功能分支
set -e

echo "=== 当前分支 ==="
git branch --show-current

echo "=== Fetching origin/main ==="
git fetch origin main

echo "=== 合并 origin/main 到当前分支 ==="
git merge origin/main --no-edit

echo "=== 合并完成，当前状态 ==="
git status --short

echo "=== 最近5条提交 ==="
git log --oneline -5
