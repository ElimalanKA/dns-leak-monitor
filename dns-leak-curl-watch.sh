#!/bin/bash

# 默认配置
VERSION="v1.0.1-interactive"
REPO_URL="https://raw.githubusercontent.com/ElimalanKA/dns-leak-monitor/main/dns-leak-curl-watch.sh"
LOGDIR="/root/dns-leak-logs"
LOGFILE="$LOGDIR/dns-leak-report.log"
DEFAULT_API_URL="http://192.168.2.251:9090/logs?level=debug"
DEFAULT_FAKEIP_PREFIX="28."
INTERVAL=5
ARCHIVE_INTERVAL=86400
PIDFILE="/tmp/dnsti.pid"
CONFIG_FILE="$LOGDIR/config.sh" # 新增配置文件路径

# --- 变量初始化与加载 ---
API_URL="$DEFAULT_API_URL"
FAKEIP_PREFIX="$DEFAULT_FAKEIP_PREFIX"
START_TIME=$(date +%s)
LAST_ARCHIVE=$START_TIME

# 函数：加载或初始化配置
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        echo "ℹ️ 从 $CONFIG_FILE 加载配置..."
        # 使用 source 加载配置，覆盖默认值
        source "$CONFIG_FILE"
    else
        echo "ℹ️ 未找到配置。使用默认配置运行。"
    fi
}

# 函数：保存当前配置到文件
save_config() {
    echo "--- 正在保存当前配置到 $CONFIG_FILE ---" > "$CONFIG_FILE"
    echo "API_URL=\"$API_URL\"" >> "$CONFIG_FILE"
    echo "FAKEIP_PREFIX=\"$FAKEIP_PREFIX\"" >> "$CONFIG_FILE"
    echo "--- 保存完成 ---" >> "$CONFIG_FILE"
}


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

show_menu() {
    echo "🛡️DNS 泄露监控工具 - dnsti $VERSION"
    echo "--------------------------------------"
    echo "当前 API: $API_URL"
    echo "当前 FakeIP: $FAKEIP_PREFIX"
    echo "--------------------------------------"
    echo "1. 安装（依赖 + 日志目录 + 快捷命令）"
    echo "2. 卸载（移除脚本 + 快捷命令）"
    echo "3. **配置管理** (修改 API/FakeIP)" # 改进点 1
    echo "4. 启动后台监控"
    echo "5. 检查并更新脚本"
    echo "6. 清理旧日志"
    echo "7. 停止后台监控"
    echo "0. 退出"
    echo -n "请选择操作 [0-7]："
    read choice
}

install_tool() {
    echo "🔧 正在安装必要依赖..."
    REQUIRED_CMDS=(jq curl awk grep tar)
    
    # 改进点 2: 尝试检测包管理器
    if command -v apt &> /dev/null; then
        PKG_CMD="apt install -y"
        apt update > /dev/null
    elif command -v dnf &> /dev/null; then
        PKG_CMD="dnf install -y"
    elif command -v yum &> /dev/null; then
        PKG_CMD="yum install -y"
    elif command -v apk &> /dev/null; then
        PKG_CMD="apk add"
    else
        echo "❌ 未检测到支持的包管理器 (apt, dnf, yum, apk)。请手动安装: jq, curl, awk, grep, tar"
        return 1
    fi
    
    $PKG_CMD "${REQUIRED_CMDS[@]}" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "⚠️ 依赖安装可能失败，请检查权限或手动安装。"
    fi

    echo "📁 创建日志目录 ($LOGDIR)..."
    mkdir -p "$LOGDIR"
    
    echo "🔗 注册快捷命令 dnsti..."
    ln -sf "$(realpath "$0")" /usr/local/bin/dnsti
    chmod +x /usr/local/bin/dnsti

    # 首次安装时保存默认配置
    save_config
    
    echo
    echo "✅ 安装完成！你现在可以使用命令：dnsti"
    echo "📦 输入 dnsti 即可启动交互菜单或自动监控"
    echo
}

uninstall_tool() {
    echo "🧹 正在卸载脚本和快捷命令..."
    rm -f /usr/local/bin/dnsti
    rm -f "$CONFIG_FILE" # 移除配置文件
    rm -rf "$LOGDIR" # 移除日志目录（可选，注释掉则只移除文件）
    echo "✅ 已彻底卸载：脚本、配置和日志目录已移除"
}

update_script() {
    echo "🔄 正在从 GitHub 拉取最新版本..."
    curl -s -o "$0.tmp" "$REPO_URL"
    if [ $? -eq 0 ]; then
        mv "$0.tmp" "$0"
        chmod +x "$0"
        echo "🚀 更新完成，正在使用新脚本重新启动监控..."
        exec "$0" --run # 使用 exec 替换当前进程
    else
        echo "❌ 更新失败，请检查网络或 REPO_URL。"
        rm -f "$0.tmp"
    fi
}

start_monitor() {
    if [ -f "$PIDFILE" ]; then
        echo "⚠️ 已有监控进程在运行（PID: $(cat "$PIDFILE")）"
        echo "   如需重新启动，请先执行菜单中的 [7] 停止后台监控"
        return
    fi

    echo "📦 启动监控（后台运行）"
    # 关键：确保在后台运行时使用当前的配置
    nohup "$0" --run > /dev/null 2>&1 &
    echo $! > "$PIDFILE"
    echo "✅ 监控已在后台启动，PID: $(cat "$PIDFILE")"
}

stop_monitor() {
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
        echo "⚠️ 未找到运行中的监控进程"
    fi
}

manage_config() { # 改进点 1: 配置管理函数
    echo "--- 配置管理 ---"
    echo "当前 API URL: $API_URL"
    echo "当前 Fake-IP Prefix: $FAKEIP_PREFIX"
    echo "1. 修改 API URL"
    echo "2. 修改 Fake-IP Prefix"
    echo "0. 返回主菜单"
    echo -n "请选择要修改的配置 [0-2]: "
    read config_choice

    case $config_choice in
        1)
            echo -n "请输入新的 API URL (当前: $API_URL): "
            read new_api
            if [[ -n "$new_api" ]]; then
                API_URL="$new_api"
                echo "✅ API URL 已更新为: $API_URL"
            else
                echo "未修改。"
            fi
            ;;
        2)
            echo -n "请输入新的 Fake-IP 前缀 (当前: $FAKEIP_PREFIX): "
            read new_prefix
            if [[ -n "$new_prefix" ]]; then
                FAKEIP_PREFIX="$new_prefix"
                echo "✅ Fake-IP Prefix 已更新为: $FAKEIP_PREFIX"
            else
                echo "未修改。"
            fi
            ;;
        0)
            return
            ;;
        *)
            echo "❌ 无效选项。"
            ;;
    esac
    # 每次修改后自动保存配置
    save_config
}


run_monitor() {
    # 只有执行 --run 才进入此函数，确保使用最新配置
    echo "🛡️ DNS 泄露监控工具 - dnsti $VERSION"
    echo "📍 当前配置参数："
    echo "   🌐 API 地址       : $API_URL"
    echo "   📁 日志目录       : $LOGDIR"
    echo "   📄 当前日志文件   : $LOGFILE"
    echo "   ⏱️ 轮询间隔       : ${INTERVAL}s"
    echo "   📦 归档周期       : 每 $((ARCHIVE_INTERVAL / 3600)) 小时"
    echo "   🧊 Fake-IP 前缀   : $FAKEIP_PREFIX"
    echo
    echo "📡 正在实时分析 Mihomo 日志（DNS 泄露 + 规则命中）..."
    echo "📁 日志写入中：$LOGFILE"
    echo

    mkdir -p "$LOGDIR"

    while true; do
        CURRENT_TIME=$(date +%s)
        ELAPSED=$((CURRENT_TIME - START_TIME))
        HH=$((ELAPSED / 3600))
        MM=$(((ELAPSED % 3600) / 60))
        SS=$((ELAPSED % 60))
        RUNTIME=$(printf "%02d:%02d:%02d" $HH $MM $SS)

        # 使用当前配置的 API_URL
        curl -s "$API_URL" | jq -r '.payload' | while read -r line; do
            if [[ "$line" == *"dns response"* ]]; then
                ip=$(echo "$line" | awk '{print $NF}')
                domain=$(echo "$line" | awk '{print $(NF-1)}')
                # 使用当前配置的 FAKEIP_PREFIX
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

        echo "📊 当前规则命中关联（仅泄露域名）：" >> "$LOGFILE"
        for d in "${!count[@]}"; do
            r="${ruleset[$d]}"
            echo "  - $d 命中规则集: ${r:-未记录}" >> "$LOGFILE"
        done
        echo >> "$LOGFILE"

        archive_logs_if_needed
        sleep "$INTERVAL"
    done
}

# 🧭 脚本入口
load_config # 启动时首先加载配置

if [[ "$1" == "--run" ]]; then
    run_monitor
else
    # 交互菜单逻辑
    while true; do
        show_menu
        case "$choice" in
            1) install_tool ;;
            2) uninstall_tool ;;
            3) manage_config ;; # 使用新函数
            4) start_monitor ;;
            5) update_script ;;
            6) clean_logs ;;
            7) stop_monitor ;; # 序号调整
            0) echo "👋 已退出"; exit 0 ;;
            *) echo "❌ 无效选项";;
        esac
        # 如果没有选择退出或启动后台，则继续循环显示菜单
        if [[ "$choice" != "0" && "$choice" != "4" ]]; then
            echo -n "按回车键继续..."
            read -r
        fi
    done
fi
