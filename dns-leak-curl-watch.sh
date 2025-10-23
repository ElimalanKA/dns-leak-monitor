#!/bin/bash

# --- 基础配置 ---
VERSION="v1.0.12-optimized-log" # Updated version: 优化了日志输出逻辑
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
        # 清空主日志文件，准备新一轮记录
        > "$LOGFILE"
        tar -czf "$LOGDIR/dns-leak-archive-$TIMESTAMP.tar.gz" -C "$LOGDIR" \
            --exclude="$(basename "$LOGFILE")" --exclude="*.tar.gz" *.log
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
    echo "🛡️ DNS 泄露监控工具 - dnsti $VERSION"
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
    stop_monitor 2>/dev/null # 尝试停止后台进程
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
    # 使用 nohup 启动，让脚本自己再次执行并进入 run_monitor
    nohup "$0" --run > /dev/null 2>&1 &
    echo $! > "$PIDFILE"
    echo "✅ 监控已在后台启动，PID: $(cat "$PIDFILE")"
    echo "    可使用 './dnsti' 查询状态或控制。"
}

stop_monitor() {
    if [ -f "$PIDFILE" ]; then
        PID=$(cat "$PIDFILE")
        if ps -p "$PID" > /dev/null; then
            # 向后台进程发送 SIGTERM，触发 run_monitor 中的 exit 陷阱
            kill -SIGTERM "$PID" && rm -f "$PIDFILE"
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
    # 使用变量封装复杂的陷阱命令，防止字符错误
    TRAP_CMD='echo "📶 收到 SIGUSR1 查询状态"; echo "当前运行时间: $(date +%H:%M:%S -d@$(( $(date +%s) - START_TIME )))"; echo "--- 泄露统计 ---"; for d in "${!count[@]}"; do r="${ruleset[$d]:-未记录}"; echo "域名: $d → ${count[$d]} 次 (规则集: $r)"; done; echo "-----------------------------"'
    
    trap "$TRAP_CMD" SIGUSR1
    trap 'echo "🛑 收到 SIGTERM 停止信号"; exit 0' SIGTERM

    echo "📡 启动实时监控（PID: $$）"
    mkdir -p "$LOGDIR"
    while true; do
        CURRENT_TIME=$(date +%s)
        ELAPSED=$((CURRENT_TIME - START_TIME))
        HH=$((ELAPSED / 3600)); MM=$(((ELAPSED % 3600) / 60)); SS=$((ELAPSED % 60))
        RUNTIME=$(printf "%02d:%02d:%02d" $HH $MM $SS)
        
        # 优化：检查 curl 调用是否成功
        LOG_PAYLOAD=$(curl -s "$API_URL" 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "❌ [$RUNTIME] 无法连接到 Mihomo API: $API_URL" >> "$LOGFILE"
            sleep "$INTERVAL"
            continue
        fi

        # 尝试从 payload 中提取日志行
        LOG_LINES=$(echo "$LOG_PAYLOAD" | jq -r '.payload' 2>/dev/null)
        
        # 清空本次循环的计数器，用于判断是否有新数据
        has_new_leak=false
        has_new_match=false

        echo "$LOG_LINES" | while IFS= read -r line; do
            # 1. DNS 泄露检测：更健壮的域名和 IP 提取
            if [[ "$line" == *"[DNS]"* && "$line" == *"-->"* ]]; then
                # 提取 Domain: 提取 '-->' 之前最后一个非空字段作为域名
                domain=$(echo "$line" | grep -oP '.*(?=\s-->)' | awk '{print $NF}')
                
                # 提取 IP: 提取第一个位于方括号 [] 内的 IP 地址 (IPv4 或 IPv6)
                ip=$(echo "$line" | grep -oP '\[\K[0-9a-fA-F.:]+' | head -n1) 

                # 检查 IP 是否是有效的 IP 地址 (IPv4 包含至少两个点, IPv6 包含冒号)
                is_valid_ip=false
                if [[ "$ip" == *.*.* ]] || [[ "$ip" == *:* ]]; then
                    is_valid_ip=true
                fi

                # 只有当 IP 是有效的 IP 格式且不是 FakeIP 时才记录泄露
                if $is_valid_ip && [[ "$ip" != "$FAKEIP_PREFIX"* ]]; then
                    # 确保域名非空，如果解析失败则使用占位符
                    if [ -z "$domain" ]; then
                        domain="DOMAIN_PARSING_ERROR"
                    fi
                    
                    # V1.0.11 增加：过滤内部噪音或已知的解析错误占位符
                    if [[ "$domain" == "cache" ]] || [[ "$domain" == "DOMAIN_PARSING_ERROR" ]]; then
                          continue # 跳过此条日志
                    fi
                    
                    ((count["$domain"]++))
                    has_new_leak=true
                    # 记录有效的 IP 地址
                    output="[$RUNTIME] ⚠️ DNS泄露: $domain → $ip（累计 ${count[$domain]} 次）"
                    echo "$output" >> "$LOGFILE"
                fi
            fi
            
            # 2. RuleSet 匹配检测：匹配 RuleSet(...) 或 Final[...]
            # 检查是否有匹配关键字
            if [[ "$line" == *"match "* ]]; then
                # 提取目标 (可能带端口，如 mqtt.szbboys.com:3885)
                target_with_port=$(echo "$line" | grep -oP '(?<=-->\s)[^: ]+')
                
                # 提取规则集名称：尝试匹配 RuleSet(...) 或 Final[...]
                if [[ "$line" =~ RuleSet\(([^\)]+)\) ]]; then
                    rule="${BASH_REMATCH[1]}"
                elif [[ "$line" =~ Final\[([^\]]+)\] ]]; then
                    rule="${BASH_REMATCH[1]}"
                else
                    rule=""
                fi

                # 移除端口，只保留域名
                target_domain=$(echo "$target_with_port" | awk -F: '{print $1}')

                # 仅当目标是有效的域名格式 (包含点号且不以数字开头) 且规则非空时才记录关联
                if [[ -n "$rule" && "$target_domain" == *.* && ! "$target_domain" =~ ^[0-9] ]]; then
                    ruleset["$target_domain"]="$rule"
                    has_new_match=true
                fi
            fi
        done
        
        # --- 日志输出判断逻辑（重点修改） ---
        
        # 只有当 'count' 数组有数据 (即发生了泄露) 或 'ruleset' 数组有新数据时，才打印统计信息
        # 简化判断：只要 'count' 数组非空，我们就认为有值得打印的统计
        if [ ${#count[@]} -gt 0 ]; then
             echo "📊 [$RUNTIME] 规则命中关联（泄露域名）：" >> "$LOGFILE"
             for d in "${!count[@]}"; do
                 r="${ruleset[$d]:-未记录}"
                 # 只有当 ruleset 中有记录时，才将规则名写入
                 if [[ "$r" != "未记录" ]]; then
                     echo "    - $d 命中规则集: ${r} (泄露 ${count[$d]} 次)" >> "$LOGFILE"
                 else
                     echo "    - $d (泄露 ${count[$d]} 次)" >> "$LOGFILE"
                 fi
             done
             echo >> "$LOGFILE"
        # 如果 count 数组为空，说明没有泄露发生，则不打印任何统计标题，保持日志简洁
        fi

        archive_logs_if_needed
        sleep "$INTERVAL"
    done
}

# --- 脚本执行入口 ---
load_config

if [[ "$1" == "--run" ]]; then
    run_monitor

# 检查后台监控状态并显示控制信息
elif [ -f "$PIDFILE" ]; then
    PID=$(cat "$PIDFILE")
    if ps -p "$PID" > /dev/null; then
        echo "🛡️ 后台监控正在运行 (PID: $PID)。"
        echo "▶️ 正在向后台进程发送状态查询信号 (SIGUSR1)..."
        # 发送 SIGUSR1 信号，后台进程会将状态打印到日志文件
        kill -SIGUSR1 "$PID" 2>/dev/null
        echo "--- 控制选项 (请在新窗口中操作) ---"
        echo "要查看实时输出或刚刚发送的状态信息: tail -f $LOGFILE"
        echo "要停止服务: dnsti 7"
        echo "要修改配置: dnsti 3"
        # 状态显示完毕，不退出，继续执行下面的主菜单循环
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
