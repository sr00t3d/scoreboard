[![🇺🇸 English](https://img.shields.io/badge/lang-English-blue.svg)](README.md) [![🇧🇷 Português](https://img.shields.io/badge/lang-Português-green.svg)](README-ptbr.md) [![🇪🇸 Español](https://img.shields.io/badge/lang-Español-yellow.svg)](README-es.md)

# scoreboard

![scoreboard cover](scoreboard-cover.webp)

[![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](https://github.com/sr00t3d/scoreboard/releases/tag/v2.0.0)
[![License](https://img.shields.io/badge/license-Apache--2.0-green.svg)](LICENSE)
[![Bash](https://img.shields.io/badge/bash-4.0%2B-orange.svg)](#requisitos)
[![PowerShell](https://img.shields.io/badge/powershell-5.1%2B%20%7C%207%2B-blue.svg)](#windows-powershell)

**CLI Multiplataforma de Auditoria do Apache Scoreboard & Workers (`scoreboard.sh` + `scoreboard.ps1`).**

O `scoreboard.sh` e o `scoreboard.ps1` consultam e analisam tabelas HTML e métricas `?auto` do Apache `mod_status` (ou snapshots via `--file`), agregam **Top IPs, Top VHosts e Top Requisições**, filtram workers (`--method`, `--vhost`, `--ip`, `--state`), ordenam por tempo de execução (`--sort ss`), suportam modo `--watch` e alertas `--warn-busy` + `--exit-code`, e exportam **Table, JSON ou CSV** sem dependências externas.

> **Inspiração Histórica:** Reimplementação limpa em Bash + Python 3.6+ e Windows PowerShell (`v2.0.0`) inspirada no clássico `scoreboard` (2011, HostGator.com, LLC).

---

## Execução Direta

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

## Exemplo de Saída Real

```text
==================================================================================================
 scoreboard.sh v2.0.0 | Source: http://127.0.0.1:18902/whm-server-status | 2026-11-24T03:13:56Z
==================================================================================================
Workers: Busy=9  Idle=1  Busy%=90.0%  Req/s=42.5  Parsed=3  Matched=3
Top Client IPs: 198.51.100.10 (2) | 203.0.113.55 (1)
Top VHosts:     sitea.com:443 (2) | siteb.com:80 (1)
Top Requests:   POST /wp-login.php (2) | GET /index.php?p=1 (1)
--------------------------------------------------------------------------------------------------
PID   M  SS(s)  CPU   CLIENT_IP      VHOST          REQUEST
----  -  -----  ----  -------------  -------------  ------------------
1011  W  45     1.25  198.51.100.10  sitea.com:443  POST /wp-login.php
1012  W  12     0.40  198.51.100.10  sitea.com:443  POST /wp-login.php
1013  R  2      0.10  203.0.113.55   siteb.com:80   GET /index.php?p=1
```

---

## Licença

Distribuído sob a licença [Apache License 2.0](LICENSE).
