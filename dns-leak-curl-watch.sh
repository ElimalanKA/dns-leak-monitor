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

# --- 配置加载与保存 ---
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
    echo "🧹 正在清理 7 天前的归档日志..."
    find "$LOGDIR" -type f -name "*.tar.gz" -mtime +7 -delete
    echo "✅ 清理完成：已删除 7 天前的归档包"
}

# --- 菜单与管理 ---
show_menu() {
    echo "🛡️DNS 泄露监控工具 - dnsti $VERSION"
    echo "--------------------------------------"
    echo "当前 API: $API_URL"
    echo "当前 FakeIP: $FAKEIP_PREFIX"
    echo "--------------------------------------"
    echo "1. 安装（依赖 + 快捷命令）"
    echo "2. 卸载（完全清理）"
    echo "3. 配置管理（修改 API/FakeIP）"
    echo "4. 启动后台监控"
    echo "5. 检查并更新脚本"
    echo "6. 清理旧日志"
    echo "7. 停止后台监控"
    echo "0. 退出"
    echo -n "请选择操作 [0-7]："
    read -r choice
}

manage_config() {
    echo "🔧 当前配置："
    echo "1. 修改 API 地址（当前：$API_URL）"
    echo "2. 修改 Fake-IP 前缀（当前：$FAKEIP_PREFIX）"
    echo "0. 返回菜单"
    echo -n "请选择操作 [0-2]："
    read -r cfg_choice

    case "$cfg_choice" in
        1) echo -n "请输入新的 API 地址：" && read -r API_URL ;;
        2) echo -n "请输入新的 Fake-IP 前缀：" && read -r FAKEIP_PREFIX ;;
        0) return ;;
        *) echo "❌ 无效选项" ;;
    esac

    save_config
    echo "✅ 配置已更新并保存"
}

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

start_monitor() {
    if [ -f "$PIDFILE" ]; then
        echo "⚠️ 已有监控进程在运行（PID: $(cat "$PIDFILE")）。请先停止。"
        return
    fi
    echo "📦 启动监控（后台运行）"
    nohup "$0" --run > /dev/null 2>&1 &
    echo $! > "$PIDFILE"
    echo "✅ 监控已在后台启动，PID: $(cat "$PIDFILE")"
    echo "   可使用 './dnsti' 查询状态或控制。"
}

stop_monitor() {
    if [ -f "$PIDFILE" ]; then
        PID=$(cat "$PIDFILE")
        if ps -p "$PID" > /dev/null; then
            kill "$PID" && rm -f "$PIDFILE"
            echo "🛑 已停止后台监控进程（PID: $PID）"
        else
            echo "⚠️ PID 文件存在，但进程不存在。正在清理残留文件。"
            rm -f "$PIDFILE"
        fi
    else
        echo "⚠️ 未找到运行中的后台监控进程"
    fi
}

run_monitor() {
    trap 'echo "📶 收到 SIGUSR1 查询状态"; echo "当前运行时间: $(date +%H:%M:%S -d@$(( $(date +%s) - $START_TIME )))"; echo "--- 泄露统计 ---"; for d in "${!count[@]}"; do r="${ruleset[$d]:-未记录}"; echo "域名: $d → ${count[$d]} 次 (规则集: $r)"; done; echo "-----------------------------"' SIGUSR1
    trap 'echo "🛑 收到 SIGTERM 停止信号"; exit 0' SIGTERM

    echo "📡 启动实时监控（PID: $$）"
    mkdir -p "$LOGDIR"

    while true; do
        CURRENT_TIME=$(date +%s)
        ELAPSED=$((CURRENT_TIME - START_TIME))
        HH=$((ELAPSED / 3600)); MM=$(((ELAPSED % 3600) / 60)); SS=$((ELAPSED % 60))
        RUNTIME=$(printf "%02d:%02d:%02d" $HH $MM $SS)

        curl -s "$API_URL" | jq -r '.payload' | while read -r line; do
            if [[ "$line" == *"dns response"* ]]; then
                ip=$(echo "$line" | awk '{print $NF}')
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

# --- 脚本执行入口 ---
load_config

if [[ "$1" == "--run" ]]; then
    run_monitor

elif [ -f "$PIDFILE" ]; then
    PID=$(cat "$PIDFILE")
    if ps -p "$PID" > /dev/null; then
        echo "🛡️ 后台监控正在运行 (PID: $PID)。"
        echo "▶️ 正在向后台进程发送状态查询信号 (SIGUSR1)..."
        kill -SIGUSR1 "$PID" 2>/dev/null
        echo "--- 控制选项 ---"
        echo "要查看实时输出: tail -f $LOGFILE"
        echo "要停止服务: ./dnsti 7"
        echo "要修改配置: ./dnsti 3"
        exit 0
    else
        echo "⚠️ 发现残留的 PID 文件 ($PIDFILE)，进程不存在。正在清理..."
        rm -f "$PIDFILE"
    fi
fi

# 默认进入菜单模式
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
