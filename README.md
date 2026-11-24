[![🇺🇸 English](https://img.shields.io/badge/lang-English-blue.svg)](README.md) [![🇧🇷 Português](https://img.shields.io/badge/lang-Português-green.svg)](README-ptbr.md) [![🇪🇸 Español](https://img.shields.io/badge/lang-Español-yellow.svg)](README-es.md)

# scoreboard

![scoreboard cover](scoreboard-cover.webp)

[![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](https://github.com/sr00t3d/scoreboard/releases/tag/v2.0.0)
[![License](https://img.shields.io/badge/license-Apache--2.0-green.svg)](LICENSE)
[![Bash](https://img.shields.io/badge/bash-4.0%2B-orange.svg)](#requirements)
[![PowerShell](https://img.shields.io/badge/powershell-5.1%2B%20%7C%207%2B-blue.svg)](#windows-powershell)

**Cross-Platform Apache `mod_status` Scoreboard & Worker Auditor CLI (Linux Bash + Windows PowerShell).**

`scoreboard.sh` and `scoreboard.ps1` fetch and parse live Apache `mod_status` HTML tables and `?auto` metrics (or saved snapshots via `--file`), aggregate **Top Client IPs, Top VHosts, and Top Requests**, filter active worker slots (`--method`, `--vhost`, `--ip`, `--state`), sort by longest-running requests (`--sort ss`), support live `--watch` monitoring and `--warn-busy` + `--exit-code` alerting, and export **Table, JSON, or CSV** with zero external dependencies.

> **Historical Inspiration:** Clean-room Bash + Python 3.6+ and Windows PowerShell `v2.0.0` reimplementation inspired by `scoreboard` (2011, HostGator.com, LLC). Eliminates silent `yum install elinks -y` mutations, `links --dump` dependency, hardcoded `http://localhost/whm-server-status`, and fragile positional `awk` column offsets.

---

## Requirements

- **Linux / macOS:** Bash 4.0+ and Python 3.6+ (standard library only)
- **Windows:** Windows PowerShell 5.1+ or PowerShell 7+ (no external modules required)

---

## Direct Execution

### Linux / macOS
```bash
curl -fsSL https://raw.githubusercontent.com/sr00t3d/scoreboard/main/scoreboard.sh -o scoreboard.sh
chmod +x scoreboard.sh
./scoreboard.sh --url http://127.0.0.1/server-status
```

### Windows PowerShell
```powershell
irm https://raw.githubusercontent.com/sr00t3d/scoreboard/main/scoreboard.ps1 -OutFile scoreboard.ps1
.\scoreboard.ps1 -Url http://127.0.0.1/server-status
```

---

## Usage

```bash
# 1. Auto-probe localhost (/whm-server-status, /server-status) & show Top IPs/VHosts/URIs
./scoreboard.sh

# 2. Filter POST requests, sort by duration (SS), and alert if BusyWorkers >= 85%
./scoreboard.sh --url https://status.example.com/server-status --method POST --warn-busy 85 --exit-code

# 3. Parse a saved server-status HTML snapshot and output JSON
./scoreboard.sh --file /tmp/server-status.html -o json

# 4. Live monitoring mode every 2 seconds
./scoreboard.sh --watch 2 --limit 20
```

```powershell
# PowerShell equivalent
.\scoreboard.ps1 -Url http://127.0.0.1/server-status -Method POST -WarnBusy 85 -ExitCode
.\scoreboard.ps1 -File C:\logs\server-status.html -Output json
```

---

## License

Licensed under the [Apache License 2.0](LICENSE).
