# DNS Leak Monitor for Mihomo for ai

This project provides a real-time DNS leak monitoring script for Mihomo, with rule-set analysis and automatic log archiving.

## Features

- Real-time detection of DNS responses not handled by Fake-IP
- RuleSet match analysis for leaked domains
- Logs stored in `/root/dns-leak-logs/`
- Automatic daily log rotation and `.tar.gz` packaging
- GitHub-based update mechanism via `run-dns-monitor.sh`

## Usage

### First-time setup

```bash
curl -O https://raw.githubusercontent.com/tiadev/dns-leak-monitor/main/run-dns-monitor.sh
chmod +x run-dns-monitor.sh
./run-dns-monitor.sh
