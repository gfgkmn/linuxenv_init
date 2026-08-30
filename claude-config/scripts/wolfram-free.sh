#!/bin/bash
# wolfram-free — 列出并清理占用 Wolfram license 席位的 idle MCP kernel.
# 用法: wolfram-free.sh        只列出
#       wolfram-free.sh kill   列出并杀掉全部 MCP kernel (含孤儿转换器进程)
echo "=== Wolfram 进程 ==="
ps aux | grep -iE "wolfram|MathKernel" | grep -v grep | grep -v wolfram-free | while read -r line; do
  pid=$(echo "$line" | awk '{print $2}')
  ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
  parent=$(ps -o command= -p "$ppid" 2>/dev/null | cut -c1-60)
  cmd=$(echo "$line" | awk '{for(i=11;i<=NF&&i<14;i++) printf "%s ", $i}')
  echo "PID $pid  <- [$parent]"
  echo "    $cmd"
done
MCP=$(pgrep -f "StartMCPServer" 2>/dev/null)
if [ -z "$MCP" ]; then echo "无 MCP kernel 占用席位."; exit 0; fi
echo
echo "占席位的 MCP kernel: $MCP"
if [ "$1" = "kill" ]; then
  kill -9 $MCP 2>/dev/null
  pkill -9 -f "Converters/Binaries.*mathlink" 2>/dev/null
  sleep 1
  echo "已清理. 复测: $(/Users/gfgkmn/Applications/bin/wolframscript -code '1+1' 2>&1 | head -1)"
else
  echo "加参数 kill 清理: ~/.claude/scripts/wolfram-free.sh kill"
fi
