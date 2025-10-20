#!/bin/bash

VERSION="v1.0.0"
REPO_URL="https://raw.githubusercontent.com/ElimalanKA/dns-leak-monitor/main/dns-leak-curl-watch.sh"
LOGDIR="/root/dns-leak-logs"
LOGFILE="$LOGDIR/dns-leak-report.log"
API_URL="http://192.168.2.251:9090/logs?level=debug"
FAKEIP_PREFIX="28."
INTERVAL=5
ARCHIVE_INTERVAL=86400
START_TIME=$(date +%s)
LAST_ARCHIVE=$START_TIME

declare -A count
declare -A ruleset

# 📦 自动归档与打包函数
archive_logs_if_needed() {
  NOW=$(date +%s)
  if (( NOW - LAST_ARCHIVE >= ARCHIVE_INTERVAL )); then
    TIMESTAMP=$(date +%Y%m%d_%H%M)
    cp "$LOGFILE" "$LOGDIR/dns-leak-report-$TIMESTAMP.log"
    > "$LOGFILE"
    tar -czf "$LOGDIR/dns-leak-archive-$TIMESTAMP.tar.gz" -C "$LOGDIR" --exclude="$(basename "$LOGFILE")" --exclude="*.tar.gz" *.log
    echo "📦 日志已归档并打包为 dns-leak-archive-$TIMESTAMP.tar.gz"
    LAST_ARCHIVE=$NOW
  fi
}

# 📦 清理函数
clean_logs() {
  echo "🧹 正在清理 7 天前的归档日志..."
  find "$LOGDIR" -type f -name "*.tar.gz" -mtime +7 -delete
  echo "✅ 清理完成：已删除 7 天前的归档包"
}

# 🧭 菜单界面
show_menu() {
  echo "🛡️ DNS 泄露监控工具 - dnsti $VERSION"
  echo "1. 安装（依赖 + 日志目录 + 快捷命令）"
  echo "2. 卸载（移除快捷命令）"
  echo "3. 运行监控脚本"
  echo "4. 检查并更新脚本"
  echo "5. 清理旧日志（保留最近 7 天）"
  echo "6. 停止后台监控"
  echo "0. 退出"
  echo -n "请选择操作 [0-6]: "
  read choice
}

# 🛠️ 安装逻辑
install_tool() {
  echo "🔧 正在安装依赖..."
  REQUIRED_CMDS=(jq curl awk grep tar)
  for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
      apt update && apt install -y "$cmd"
    fi
  done

  echo "📁 创建日志目录..."
  mkdir -p "$LOGDIR"

  echo "🔗 创建快捷命令 dnsti..."
  ln -sf "$(realpath "$0")" /usr/local/bin/dnsti
  chmod +x /usr/local/bin/dnsti

  echo
  echo "✅ 安装完成！你现在可以使用快捷命令：dnsti"
  echo "📦 运行方式：只需输入 dnsti 即可启动交互菜单"
  echo
}

# 🧹 卸载逻辑
uninstall_tool() {
  rm -f /usr/local/bin/dnsti
  echo "✅ 快捷命令 dnsti 已移除"
}

# 🔄 更新逻辑
update_script() {
  echo "🔄 正在从 GitHub 拉取最新版本..."
  curl -s -o "$0" "$REPO_URL"
  chmod +x "$0"
  echo "✅ 脚本已更新，请重新运行以加载新版本。"
  exit 0
}

# 🚀 主监控逻辑
run_monitor() {
## 输出当前配置参数
  echo "🛡️ DNS 泄露监控工具 - dnsti $VERSION"
  echo "📍 当前配置参数："
  echo "   🌐 API 地址       : $API_URL"
  echo "   📁 日志目录       : $LOGDIR"
  echo "   📄 当前日志文件   : $LOGFILE"
  echo "   ⏱️ 轮询间隔       : ${INTERVAL}s"
  echo "   📦 归档周期       : 每 $((ARCHIVE_INTERVAL / 3600)) 小时"
  echo "   🧊 Fake-IP 前缀   : $FAKEIP_PREFIX"
  echo

  echo "📡 正在实时分析 Mihomo 日志（DNS 泄露 + 规则命中）..."
  echo "📦 启动监控（后台运行）"
  nohup "$0" --run > /dev/null 2>&1 &
  echo $! > /tmp/dnsti.pid
  echo "✅ 监控已在后台启动，PID: $(cat /tmp/dnsti.pid)"
  echo
  mkdir -p "$LOGDIR"

  while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    HH=$((ELAPSED / 3600))
    MM=$(((ELAPSED % 3600) / 60))
    SS=$((ELAPSED % 60))
    RUNTIME=$(printf "%02d:%02d:%02d" $HH $MM $SS)

    curl -s "$API_URL" | jq -r '.payload' | while read -r line; do
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

      if [[ "$line" == *"match RuleSet("* ]]; then
        domain=$(echo "$line" | grep -oP '(?<=--\>\s)[^: ]+')
        rule=$(echo "$line" | grep -oP 'RuleSet\(\K[^)]+' | head -n1)
        if [[ -n "$domain" && -n "$rule" ]]; then
          ruleset["$domain"]="$rule"
        fi
      fi
    done

    echo "📊 当前规则命中关联（仅泄露域名）：" >> "$LOGFILE"
    for d in "${!count[@]}"; do
      r="${ruleset[$d]}"
      echo "  - $d 命中规则集: ${r:-未记录}" >> "$LOGFILE"
    done
    echo >> "$LOGFILE"

    archive_logs_if_needed
    sleep "$INTERVAL"
  done
}

## 🛑 停止监控
stop_monitor() {
  if [ -f /tmp/dnsti.pid ]; then
    PID=$(cat /tmp/dnsti.pid)
    kill "$PID" && rm -f /tmp/dnsti.pid
    echo "🛑 已停止后台监控进程（PID: $PID）"
  else
    echo "⚠️ 未找到运行中的监控进程"
  fi
}

# 🧭 菜单入口
if [[ "$1" != "--run" ]]; then
  show_menu
  case "$choice" in
    1) install_tool ;;
    2) uninstall_tool ;;
    3) exec "$0" --run ;;
    4) update_script ;;
    5) clean_logs ;;   
    6) stop_monitor ;;
    0) echo "👋 已退出"; exit 0 ;;
    *) echo "❌ 无效选项"; exit 1 ;;
  esac
else
  run_monitor
fi
