## 🛡️ Mihomo DNS 泄露监控工具 for AI
本项目提供一个实时 DNS 泄露监控脚本，专为 Mihomo 设计，支持规则集分析与自动日志归档。

✨ 功能特色

📡 实时检测未被 Fake-IP 处理的 DNS 响应

📊 分析泄露域名对应的规则集命中情况

📁 所有日志集中存储于 /root/dns-leak-logs/

📦 每 24 小时自动归档 .log 文件并打包为 .tar.gz

🧭 提供交互式菜单：安装、卸载、运行、更新

🔗 安装后可使用快捷命令 dnsti 启动工具

## 🚀 使用方式
## ✅ 首次安装
```bash
curl -O https://raw.githubusercontent.com/ElimalanKA/dns-leak-monitor/main/dns-leak-curl-watch.sh
chmod +x dns-leak-curl-watch.sh
./dns-leak-curl-watch.sh
```

## 安装完成后，系统会自动创建快捷命令
```bash
dnsti
```
