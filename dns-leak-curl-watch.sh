#!/bin/bash

# 📦 自动检测并安装依赖
REQUIRED_CMDS=(jq curl awk grep tar)
for cmd in "${REQUIRED_CMDS[@]}"; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "🔧 未检测到依赖：$cmd，正在尝试安装..."
    apt update && apt install -y "$cmd"
    if ! command -v "$cmd" &> /dev/null; then
      echo "❌ 安装 $cmd 失败，请手动安装后重试。"
      exit 1
    fi
  fi
done
echo "✅ 所有依赖已准备好，开始执行脚本..."

# 📁 日志目录与文件设置
LOGDIR="/root/dns-leak-logs"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/dns-leak-report.log"

# 🌐 Mihomo Controller API 地址
API_URL="http://192.168.2.251:9090/logs?level=debug"
FAKEIP_PREFIX="28."
INTERVAL=5  # 每次轮询间隔秒数
START_TIME=$(date +%s)

# ⏱️ 自动归档设置
ARCHIVE_INTERVAL=86400  # 每 24 小时
LAST_ARCHIVE=$START_TIME

# 🧠 数据结构
declare -A count
declare -A ruleset

echo "📡 正在实时分析 Mihomo 日志（DNS 泄露 + 规则命中）..."
echo "按 Ctrl+C 停止"
echo

# 📦 自动归档与打包函数
archive_logs_if_needed() {
  NOW=$(date +%s)
  if (( NOW - LAST_ARCHIVE >= ARCHIVE_INTERVAL )); then
    TIMESTAMP=$(date +%Y%m%d_%H%M)

    # 归档当前日志
    cp "$LOGFILE" "$LOGDIR/dns-leak-report-$TIMESTAMP.log"
    > "$LOGFILE"

    # 打包所有 .log 文件（排除已有压缩包）
    tar -czf "$LOGDIR/dns-leak-archive-$TIMESTAMP.tar.gz" -C "$LOGDIR" --exclude="*.tar.gz" *.log

    echo "📦 日志已归档并打包为 dns-leak-archive-$TIMESTAMP.tar.gz"
    LAST_ARCHIVE=$NOW
  fi
}

# 🔁 主循环
while true; do
  CURRENT_TIME=$(date +%s)
  ELAPSED=$((CURRENT_TIME - START_TIME))
  HH=$((ELAPSED / 3600))
  MM=$(((ELAPSED % 3600) / 60))
  SS=$((ELAPSED % 60))
  RUNTIME=$(printf "%02d:%02d:%02d" $HH $MM $SS)

  curl -s "$API_URL" | jq -r '.payload' | while read -r line; do
    # DNS 响应分析
    if [[ "$line" == *"dns response"* ]]; then
      ip=$(echo "$line" | awk '{print $NF}')
      domain=$(echo "$line" | awk '{print $(NF-1)}')

      if [[ $ip != $FAKEIP_PREFIX* ]]; then
        ((count["$domain"]++))
        output="[$RUNTIME] ⚠️ 泄露域名: $domain → $ip（累计 ${count[$domain]} 次）"
        echo "$output"
        echo "$output" >> "$LOGFILE"
      fi
    fi

    # 规则命中分析
    if [[ "$line" == *"match RuleSet("* ]]; then
      domain=$(echo "$line" | grep -oP '(?<=--\>\s)[^: ]+')
      rule=$(echo "$line" | grep -oP 'RuleSet\(\K[^)]+' | head -n1)

      if [[ -n "$domain" && -n "$rule" ]]; then
        ruleset["$domain"]="$rule"
      fi
    fi
  done

  # 📊 输出规则命中关联（仅泄露域名）
  echo "📊 当前规则命中关联（仅泄露域名）：" >> "$LOGFILE"
  for d in "${!count[@]}"; do
    r="${ruleset[$d]}"
    echo "  - $d 命中规则集: ${r:-未记录}" >> "$LOGFILE"
  done
  echo >> "$LOGFILE"

  archive_logs_if_needed
  sleep "$INTERVAL"
done
