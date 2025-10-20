#!/bin/bash

# --- 基础配置 ---
VERSION="v1.0.5-control-query"
REPO_URL="https://raw.githubusercontent.com/ElimalanKA/dns-leak-monitor/main/dns-leak-curl-watch.sh"
LOGDIR="/root/dns-leak-logs"
LOGFILE="$LOGDIR/dns-leak-report.log"
DEFAULT_API_URL="http://192.168.2.251:9090/logs?level=debug"
DEFAULT_FAKEIP_PREFIX="28."
INTERVAL=5
ARCHIVE_INTERVAL=86400
PIDFILE="/tmp/dnsti.pid"
CONFIG_FILE="$LOGDIR/config.sh"

# --- 变量初始化 ---
API_URL="$DEFAULT_API_URL"
FAKEIP_PREFIX="$DEFAULT_FAKEIP_PREFIX"
START_TIME=$(date +%s)
LAST_ARCHIVE=$START_TIME
declare -A count
declare -A ruleset

# --- 配置加载与保存 (不变) ---
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
}
save_config() {
    echo "API_URL=\"$API_URL\"" > "$CONFIG_FILE"
    echo "FAKEIP_PREFIX=\"$FAKEIP_PREFIX\"" >> "$CONFIG_FILE"
}

# --- 核心功能函数 ---

archive_logs_if_needed() {
    # ... (归档函数，保持不变) ...
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

clean_logs() {
    # ... (清理函数，保持不变) ...
    echo "🧹 正在清理 7 天前的归档日志..."
    find "$LOGDIR" -type f -name "*.tar.gz" -mtime +7 -delete
    echo "✅ 清理完成：已删除 7 天前的归档包"
}

# --- 菜单与管理 (不变) ---
show_menu() {
    echo "🛡️DNS 泄露监控工具 - dnsti $VERSION"
    echo "--------------------------------------"
    echo "当前 API: $API_URL"
    echo "当前 FakeIP: $FAKEIP_PREFIX"
    echo "--------------------------------------"
    echo "1. 安装（依赖 + 快捷命令）"
    echo "2. 卸载（完全清理）"
    echo "3. **配置管理** (修改 API/FakeIP)"
    echo "4. 启动后台监控"
    echo "5. 检查并更新脚本"
    echo "6. 清理旧日志"
    echo "7. 停止后台监控"
    echo "0. 退出"
    echo -n "请选择操作 [0-7]："
    read -r choice
}
# ... (install_tool, uninstall_tool, update_script, manage_config 函数定义保持不变，请自行复制或参考上文) ...

install_tool() {
    echo "🔧 正在安装必要依赖和快捷方式..."
    REQUIRED_CMDS=(jq curl awk grep tar)
    
    if command -v apt &> /dev/null; then
        PKG_CMD="apt install -y"
        apt update > /dev/null 2>&1
    elif command -v dnf &> /dev/null; then
        PKG_CMD="dnf install -y"
    elif command -v yum &> /dev/null; then
        PKG_CMD="yum install -y"
    elif command -v apk &> /dev/null; then
        PKG_CMD="apk add"
    else
        echo "❌ 未检测到支持的包管理器 (apt, dnf, yum, apk)。请手动安装依赖。"
        return 1
    fi
    
    $PKG_CMD "${REQUIRED_CMDS[@]}" > /dev/null 2>&1
    
    echo "📁 创建日志目录 ($LOGDIR)..."
    mkdir -p "$LOGDIR"
    
    echo "🔗 注册快捷命令 dnsti..."
    ln -sf "$(realpath "$0")" /usr/local/bin/dnsti
    chmod +x /usr/local/bin/dnsti

    save_config
    echo "✅ 安装完成！"
}

uninstall_tool() {
    echo "🧹 正在执行完全卸载..."
    rm -f /usr/local/bin/dnsti
    rm -f "$0"
    rm -rf "$LOGDIR"
    rm -f "$CONFIG_FILE"
    echo "✅ 已彻底卸载：脚本、配置、日志和快捷命令均已移除。"
}

update_script() {
    echo "🔄 正在从 GitHub 拉取最新版本..."
    curl -s -o "$0.tmp" "$REPO_URL"
    if [ $? -eq 0 ]; then
        mv "$0.tmp" "$0"
        chmod +x "$0"
        echo "🚀 更新完成。请重新执行脚本以应用更新的逻辑。"
        exit 0
    else
        echo "❌ 更新失败，请检查网络或 REPO_URL。"
        rm -f "$0.tmp"
    fi
}

# --- 状态查询/控制/停止 (新的信号处理函数) ---

# 函数：后台进程接收到信号后执行
handle_signal() {
    # 捕获 SIGUSR1 (查询状态)
    if [ "$1" == "SIGUSR1" ]; then
        echo ""
        echo "------------------------------------"
        echo "后台进程收到状态查询信号 (SIGUSR1)。"
        echo "当前运行时间: $(date +%H:%M:%S -d@$(( $(date +%s) - $START_TIME )))"
        
        # 打印当前泄露统计
        if [ ${#count[@]} -eq 0 ]; then
             echo "暂无泄露记录。"
        else
             echo "--- 泄露统计 ---"
             for d in "${!count[@]}"; do
                 r="${ruleset[$d]:-未记录}"
                 echo "域名: $d -> $ {count[$d]} 次 (规则集: $r)"
             done
        fi
        echo "------------------------------------"
    fi
}

start_monitor() {
    if [ -f "$PIDFILE" ]; then
        echo "⚠️ 已有监控进程在运行（PID: $(cat "$PIDFILE")）。请先停止。"
        return
    fi
    echo "📦 启动监控（后台运行）"
    # 关键：将脚本作为 --run 启动，并添加信号处理器
    nohup bash -c 'trap "handle_signal SIGUSR1" SIGUSR1; trap "exit" SIGTERM; exec "$0" --run' "$0" > /dev/null 2>&1 &
    echo $! > "$PIDFILE"
    echo "✅ 监控已在后台启动，PID: $(cat "$PIDFILE")"
    echo "   请稍后再次运行 './dnsti' 来查询状态或控制。"
}

stop_monitor() {
    # ... (stop_monitor 函数，与上一个版本相同，但现在它会发送 SIGTERM)
    if [ -f "$PIDFILE" ]; then
        PID=$(cat "$PIDFILE")
        if ps -p "$PID" > /dev/null; then
            kill "$PID" && rm -f "$PIDFILE"
            echo "🛑 已停止后台监控进程（PID: $PID）"
        else
            echo "⚠️ PID 文件存在 ($PIDFILE)，但进程不存在。正在清理残留文件。"
            rm -f "$PIDFILE"
        fi
    else
        echo "⚠️ 未找到运行中的后台监控进程"
    fi
}


# --- 监控核心逻辑 ---
run_monitor() {
    echo "📡 启动实时监控（PID: $$）"
    mkdir -p "$LOGDIR"

    while true; do
        # 1. 日志拉取与分析
        # ... (保持与上一个版本相同的日志处理逻辑) ...
        CURRENT_TIME=$(date +%s)
        ELAPSED=$((CURRENT_TIME - START_TIME))
        HH=$((ELAPSED / 3600)); MM=$(((ELAPSED % 3600) / 60)); SS=$((ELAPSED % 60))
        RUNTIME=$(printf "%02d:%02d:%02d" $HH $MM $SS)

        curl -s "$API_URL" | jq -r '.payload' | while read -r line; do
            if [[ "$line" == *"dns response"* ]]; then
                ip=$(echo "$line" | awk '{print $NF}')
                domain=$(echo "$line" | awk '{print $(NF-1)}')
                if [[ "$ip" != "$FAKEIP_PREFIX"* ]]; then
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
        
        # 2. 打印状态到日志
        echo "📊 [$RUNTIME] 规则命中关联（泄露域名）：" >> "$LOGFILE"
        for d in "${!count[@]}"; do
            r="${ruleset[$d]:-未记录}"
            echo "  - $d 命中规则集: ${r}" >> "$LOGFILE"
        done
        echo >> "$LOGFILE"

        archive_logs_if_needed
        sleep "$INTERVAL"
    done
}

# --- 脚本执行入口 (重点修改) ---

load_config # 启动时首先加载配置

if [[ "$1" == "--run" ]]; then
  # 仅当明确带 --run 时才作为后台服务启动 (执行主循环)
  run_monitor
  
elif [ -f "$PIDFILE" ]; then
    # 检查是否在后台运行 (PID文件存在)
    PID=$(cat "$PIDFILE")
    if ps -p "$PID" > /dev/null; then
        echo "🛡️ 后台监控正在运行 (PID: $PID)。"
        
        # 提示用户发送信号来查询状态
        echo "▶️ 正在向后台进程发送状态查询信号 (SIGUSR1)..."
        kill -SIGUSR1 "$PID" 2>/dev/null
        
        # 提示用户如何管理
        echo "--- 控制选项 ---"
        echo "要查看实时输出: tail -f $LOGFILE"
        echo "要停止服务: ./dnsti 7"
        echo "要修改配置: ./dnsti 3"
        exit 0
    else
        echo "⚠️ 发现残留的 PID 文件 ($PIDFILE)，进程不存在。正在清理..."
        rm -f "$PIDFILE"
        # 流程进入菜单模式
    fi
fi

# 如果没有后台进程在运行，则进入菜单模式 (默认行为)
while true; do
    show_menu
    case "$choice" in
        1) install_tool ;;
        2) uninstall_tool ;;
        3) manage_config ;;
        4) start_monitor ;;
        5) update_script ;;
        6) clean_logs ;;
        7) stop_monitor ;;
        0) echo "👋 已退出"; exit 0 ;;
        *) echo "❌ 无效选项";;
    esac
    
    if [[ "$choice" != "0" && "$choice" != "4" ]]; then
      echo -n "按回车键继续..."
      read -r
    fi
done
