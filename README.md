# DNS Leak Monitor for Mihomo for ai

This project provides a real-time DNS leak monitoring script for Mihomo, with rule-set analysis and automatic log archiving.

## Features

- Real-time detection of DNS responses not handled by Fake-IP
- RuleSet match analysis for leaked domains
- Logs stored in `/root/dns-leak-logs/`
- Automatic daily log rotation and `.tar.gz` packaging

## Usage

### First-time setup

```bash
curl -O https://raw.githubusercontent.com/ElimalanKA/dns-leak-monitor/refs/heads/main/dns-leak-curl-watch.sh
```
