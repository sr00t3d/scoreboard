#!/usr/bin/env bash
# ==============================================================================
# scoreboard.sh — Cross-Platform Apache Scoreboard & Worker Auditor CLI (v2.0.0)
# ==============================================================================
# Clean-room Bash + Python 3.6+ reimplementation inspired by scoreboard (2011,
# HostGator.com, LLC).
#
# Eliminates silent package installs (yum install elinks -y), links --dump
# dependency, hardcoded http://localhost/whm-server-status, and fragile
# positional awk column parsing.
#
# Adds header-aware Apache mod_status HTML & ?auto parser, multi-endpoint
# auto-discovery, Top Client IPs / VHosts / URIs aggregation, worker filtering,
# --watch live mode, --warn-busy + --exit-code alerting, and table/json/csv.
#
# License: Apache-2.0
# Author:  Percio Castelo (https://perciocastelo.com.br)
# Repo:    https://github.com/sr00t3d/scoreboard
# ==============================================================================

set -euo pipefail

readonly SCRIPT_NAME="scoreboard.sh"
readonly SCRIPT_VERSION="2.0.0"

URL=""
FILE_PATH=""
TIMEOUT_SEC="8"
INSECURE=0
AUTH_USER=""
CUSTOM_HEADER=""
METHOD_FILTER=""
VHOST_FILTER=""
IP_FILTER=""
STATE_FILTER=""
SORT_BY="ss"
LIMIT_ROWS="50"
TOP_MODE="all"
WATCH_SEC="0"
WARN_BUSY="90"
EXIT_CODE_MODE=0
OUTPUT_FMT="table"
QUIET=0
NO_COLOR=0

C_RED=""
C_GREEN=""
C_YELLOW=""
C_CYAN=""
C_BOLD=""
C_RESET=""

init_colors() {
  if [[ "$NO_COLOR" -eq 0 && -t 1 && "$OUTPUT_FMT" == "table" ]]; then
    C_RED=$'\033[0;31m'
    C_GREEN=$'\033[0;32m'
    C_YELLOW=$'\033[0;33m'
    C_CYAN=$'\033[0;36m'
    C_BOLD=$'\033[1m'
    C_RESET=$'\033[0m'
  fi
}

usage() {
  cat <<EOF
${SCRIPT_NAME} v${SCRIPT_VERSION} — Apache Scoreboard & Worker Auditor CLI

Usage:
  ${SCRIPT_NAME} [options]

Source Options:
  -u, --url <url>         Apache server-status URL (default: auto-probe localhost)
  -f, --file <path>       Parse a saved mod_status HTML or ?auto file instead of HTTP
  --timeout <sec>         HTTP request timeout in seconds (default: 8)
  -k, --insecure          Allow self-signed TLS certificates
  --auth <user:pass>      HTTP Basic authentication credentials
  --header <K:V>          Custom HTTP header (e.g. "Host: status.internal")

Filter & Aggregation Options:
  --method <GET|POST|..>  Filter workers by HTTP method
  --vhost <substr>        Filter workers by VHost substring
  --ip <substr>           Filter workers by Client IP substring
  --state <M>             Filter workers by mode char (e.g. W, R, K, C, L)
  --sort <field>          Sort workers by: ss (default), cpu, req, ip, vhost
  --limit <N>             Max worker rows to show (default: 50, 0 = all)
  --top <mode>            Top summary blocks: all (default), ip, vhost, uri, none
  --watch <sec>           Refresh continuously every <sec> seconds
  --warn-busy <pct>       Busy worker percentage threshold (default: 90)
  --exit-code             Exit 2 if busy workers >= --warn-busy (or HTTP error)
  -o, --output <fmt>      Output format: table (default), json, csv
  -q, --quiet             Minimal output
  --no-color              Disable ANSI colors
  -h, --help              Show this help
  -v, --version           Show version

Examples:
  ${SCRIPT_NAME}
  ${SCRIPT_NAME} --url http://127.0.0.1/server-status --sort ss --limit 25
  ${SCRIPT_NAME} --file /tmp/whm-server-status.html -o json
  ${SCRIPT_NAME} --method POST --top ip --warn-busy 85 --exit-code
  ${SCRIPT_NAME} --watch 2 --limit 20
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      -v|--version) printf '%s %s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"; exit 0 ;;
      -u|--url)
        [[ $# -ge 2 ]] || { printf '[ERR] --url requires a URL.\n' >&2; exit 1; }
        URL="$2"; shift 2 ;;
      -f|--file)
        [[ $# -ge 2 ]] || { printf '[ERR] --file requires a path.\n' >&2; exit 1; }
        FILE_PATH="$2"; shift 2 ;;
      --timeout)
        [[ $# -ge 2 ]] || { printf '[ERR] --timeout requires seconds.\n' >&2; exit 1; }
        TIMEOUT_SEC="$2"; shift 2 ;;
      -k|--insecure) INSECURE=1; shift ;;
      --auth)
        [[ $# -ge 2 ]] || { printf '[ERR] --auth requires user:pass.\n' >&2; exit 1; }
        AUTH_USER="$2"; shift 2 ;;
      --header)
        [[ $# -ge 2 ]] || { printf '[ERR] --header requires "Key: Value".\n' >&2; exit 1; }
        CUSTOM_HEADER="$2"; shift 2 ;;
      --method)
        [[ $# -ge 2 ]] || { printf '[ERR] --method requires a method.\n' >&2; exit 1; }
        METHOD_FILTER="$2"; shift 2 ;;
      --vhost)
        [[ $# -ge 2 ]] || { printf '[ERR] --vhost requires a pattern.\n' >&2; exit 1; }
        VHOST_FILTER="$2"; shift 2 ;;
      --ip)
        [[ $# -ge 2 ]] || { printf '[ERR] --ip requires a pattern.\n' >&2; exit 1; }
        IP_FILTER="$2"; shift 2 ;;
      --state)
        [[ $# -ge 2 ]] || { printf '[ERR] --state requires a state char.\n' >&2; exit 1; }
        STATE_FILTER="$2"; shift 2 ;;
      --sort)
        [[ $# -ge 2 ]] || { printf '[ERR] --sort requires ss|cpu|req|ip|vhost.\n' >&2; exit 1; }
        SORT_BY="$2"; shift 2 ;;
      --limit)
        [[ $# -ge 2 ]] || { printf '[ERR] --limit requires an integer.\n' >&2; exit 1; }
        LIMIT_ROWS="$2"; shift 2 ;;
      --top)
        [[ $# -ge 2 ]] || { printf '[ERR] --top requires all|ip|vhost|uri|none.\n' >&2; exit 1; }
        TOP_MODE="$2"; shift 2 ;;
      --watch)
        [[ $# -ge 2 ]] || { printf '[ERR] --watch requires seconds.\n' >&2; exit 1; }
        WATCH_SEC="$2"; shift 2 ;;
      --warn-busy)
        [[ $# -ge 2 ]] || { printf '[ERR] --warn-busy requires 1..100.\n' >&2; exit 1; }
        WARN_BUSY="$2"; shift 2 ;;
      --exit-code) EXIT_CODE_MODE=1; shift ;;
      -o|--output)
        [[ $# -ge 2 ]] || { printf '[ERR] --output requires table|json|csv.\n' >&2; exit 1; }
        OUTPUT_FMT="$2"; shift 2 ;;
      -q|--quiet) QUIET=1; shift ;;
      --no-color) NO_COLOR=1; shift ;;
      *)
        printf '[ERR] Unknown option: %s\n' "$1" >&2
        exit 1 ;;
    esac
  done

  case "$SORT_BY" in
    ss|cpu|req|ip|vhost) ;;
    *) printf '[ERR] Invalid --sort: %s\n' "$SORT_BY" >&2; exit 1 ;;
  esac
  case "$TOP_MODE" in
    all|ip|vhost|uri|none) ;;
    *) printf '[ERR] Invalid --top: %s\n' "$TOP_MODE" >&2; exit 1 ;;
  esac
  case "$OUTPUT_FMT" in
    table|json|csv) ;;
    *) printf '[ERR] Invalid --output: %s\n' "$OUTPUT_FMT" >&2; exit 1 ;;
  esac
}

main() {
  parse_args "$@"

  if ! command -v python3 >/dev/null 2>&1; then
    printf '[ERR] python3 is required.\n' >&2
    exit 1
  fi

  init_colors

  local py_script
  py_script="$(cat <<'PYEOF'
import base64
import collections
import csv
import html
import io
import json
import re
import ssl
import sys
import time
import urllib.error
import urllib.request
from html.parser import HTMLParser

(
    url_opt, file_opt, timeout_s, insecure_s, auth_user, custom_hdr,
    method_f, vhost_f, ip_f, state_f, sort_by, limit_s, top_mode,
    watch_s, warn_busy_s, exit_code_s, fmt, quiet_s,
    script_name, script_version,
    c_red, c_green, c_yellow, c_cyan, c_bold, c_reset
) = sys.argv[1:27]

timeout = float(timeout_s)
insecure = insecure_s == "1"
limit_rows = int(limit_s)
watch_sec = int(watch_s)
warn_busy = float(warn_busy_s)
exit_code_mode = exit_code_s == "1"
quiet = quiet_s == "1"

DEFAULT_URLS = [
    "http://127.0.0.1/whm-server-status",
    "http://127.0.0.1/server-status",
    "http://localhost/whm-server-status",
    "http://localhost/server-status",
]


class StatusTableParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.tables = []
        self._in_table = False
        self._in_tr = False
        self._in_cell = False
        self._in_pre = False
        self._cur_table = []
        self._cur_row = []
        self._cur_cell = []
        self._cur_is_hdr = False
        self.pres = []
        self._cur_pre = []

    def handle_starttag(self, tag, attrs):
        t = tag.lower()
        if t == "table":
            self._in_table = True
            self._cur_table = []
        elif t == "tr" and self._in_table:
            self._in_tr = True
            self._cur_row = []
        elif t in ("th", "td") and self._in_tr:
            self._in_cell = True
            self._cur_cell = []
            self._cur_is_hdr = (t == "th")
        elif t == "pre":
            self._in_pre = True
            self._cur_pre = []

    def handle_endtag(self, tag):
        t = tag.lower()
        if t == "table" and self._in_table:
            if self._cur_table:
                self.tables.append(self._cur_table)
            self._in_table = False
        elif t == "tr" and self._in_tr:
            if self._cur_row:
                self._cur_table.append(self._cur_row)
            self._in_tr = False
        elif t in ("th", "td") and self._in_cell:
            txt = " ".join("".join(self._cur_cell).split())
            self._cur_row.append((self._cur_is_hdr, txt))
            self._in_cell = False
        elif t == "pre" and self._in_pre:
            self.pres.append("".join(self._cur_pre))
            self._in_pre = False

    def handle_data(self, data):
        if self._in_cell:
            self._cur_cell.append(data)
        if self._in_pre:
            self._cur_pre.append(data)


def fetch_url(u):
    req = urllib.request.Request(u, headers={"User-Agent": f"{script_name}/{script_version}"})
    if auth_user and ":" in auth_user:
        tok = base64.b64encode(auth_user.encode("utf-8")).decode("ascii")
        req.add_header("Authorization", f"Basic {tok}")
    if custom_hdr and ":" in custom_hdr:
        k, v = custom_hdr.split(":", 1)
        req.add_header(k.strip(), v.strip())
    ctx = None
    if insecure and u.lower().startswith("https://"):
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
    with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
        return resp.read().decode("utf-8", errors="replace")


def load_source():
    if file_opt:
        with open(file_opt, "r", encoding="utf-8", errors="replace") as f:
            return file_opt, f.read()
    candidates = [url_opt] if url_opt else DEFAULT_URLS
    last_err = None
    for cand in candidates:
        try:
            body = fetch_url(cand)
            if any(k in body for k in ("Apache Server Status", "BusyWorkers", "Total Accesses", "<table", "Scoreboard:")):
                return cand, body
        except Exception as e:
            last_err = e
            continue
    raise RuntimeError(f"Failed to fetch Apache server-status ({last_err})")


def to_float(s, default=0.0):
    try:
        return float(re.sub(r'[^0-9.-]', '', s))
    except Exception:
        return default


def to_int(s, default=0):
    try:
        return int(float(re.sub(r'[^0-9.-]', '', s)))
    except Exception:
        return default


def parse_status_body(raw_body):
    metrics = {
        "busy_workers": None,
        "idle_workers": None,
        "total_accesses": None,
        "req_per_sec": None,
        "cpu_load": None,
        "uptime": None,
        "scoreboard": "",
    }
    plain_text = re.sub(r'<[^>]+>', '\n', html.unescape(raw_body))
    for line in plain_text.splitlines():
        line = line.strip()
        if not line:
            continue
        m_bw = re.match(r'^(\d+)\s+requests currently being processed,\s+(\d+)\s+idle workers', line)
        if m_bw:
            metrics["busy_workers"] = int(m_bw.group(1))
            metrics["idle_workers"] = int(m_bw.group(2))
        elif line.startswith("BusyWorkers:"):
            metrics["busy_workers"] = to_int(line.split(":", 1)[1])
        elif line.startswith("IdleWorkers:"):
            metrics["idle_workers"] = to_int(line.split(":", 1)[1])
        elif line.startswith("Total Accesses:"):
            metrics["total_accesses"] = to_int(line.split(":", 1)[1])
        elif line.startswith("ReqPerSec:"):
            metrics["req_per_sec"] = to_float(line.split(":", 1)[1])
        elif line.startswith("CPULoad:"):
            metrics["cpu_load"] = to_float(line.split(":", 1)[1])
        elif line.startswith("Server uptime:"):
            metrics["uptime"] = line.split(":", 1)[1].strip()
        elif line.startswith("Scoreboard:"):
            metrics["scoreboard"] = line.split(":", 1)[1].strip()
        else:
            m_rps = re.search(r'([0-9.]+)\s+requests/sec', line)
            if m_rps and metrics["req_per_sec"] is None:
                metrics["req_per_sec"] = float(m_rps.group(1))

    parser = StatusTableParser()
    parser.feed(raw_body)
    if not metrics["scoreboard"]:
        for p in parser.pres:
            sb = "".join(p.split())
            if sb and re.match(r'^[._SRWKDCLGI]+$', sb):
                metrics["scoreboard"] = sb
                break

    workers = []
    for tbl in parser.tables:
        if len(tbl) < 2:
            continue
        first_row = tbl[0]
        hdrs = [c[1].strip().lower() for c in first_row]
        if not any(h in hdrs for h in ("client", "vhost", "request", "pid", "m")):
            continue
        col_map = {h: idx for idx, h in enumerate(hdrs)}
        for row in tbl[1:]:
            if all(c[0] for c in row):
                continue
            vals = [c[1] for c in row]
            def get_col(*names):
                for n in names:
                    if n in col_map and col_map[n] < len(vals):
                        return vals[col_map[n]].strip()
                return ""

            pid = get_col("pid")
            mode = get_col("m")
            cpu = to_float(get_col("cpu"))
            ss = to_int(get_col("ss"))
            req_ms = to_int(get_col("req"))
            client = get_col("client")
            vhost = get_col("vhost")
            request = get_col("request")
            # Split method & URI from request string (e.g. "GET /index.php HTTP/1.1")
            method = "-"
            uri = request
            m_req = re.match(r'^([A-Z]+)\s+(\S+)', request)
            if m_req:
                method = m_req.group(1)
                uri = m_req.group(2)

            workers.append({
                "pid": pid or "-",
                "state": mode or "-",
                "cpu": cpu,
                "ss": ss,
                "req_ms": req_ms,
                "client_ip": client or "-",
                "vhost": vhost or "-",
                "method": method,
                "uri": uri or "-",
                "request": request or "-",
            })

    return metrics, workers


def run_once():
    ts_utc = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    src_label, raw = load_source()
    metrics, workers = parse_status_body(raw)

    filtered = []
    for w in workers:
        if method_f and w["method"].upper() != method_f.upper():
            continue
        if vhost_f and vhost_f.lower() not in w["vhost"].lower():
            continue
        if ip_f and ip_f not in w["client_ip"]:
            continue
        if state_f and w["state"].upper() != state_f.upper():
            continue
        filtered.append(w)

    if sort_by == "ss":
        filtered.sort(key=lambda x: (-x["ss"], -x["cpu"]))
    elif sort_by == "cpu":
        filtered.sort(key=lambda x: (-x["cpu"], -x["ss"]))
    elif sort_by == "req":
        filtered.sort(key=lambda x: (-x["req_ms"], -x["ss"]))
    elif sort_by == "ip":
        filtered.sort(key=lambda x: (x["client_ip"], -x["ss"]))
    elif sort_by == "vhost":
        filtered.sort(key=lambda x: (x["vhost"], -x["ss"]))

    # Top aggregations (over filtered workers)
    active = [w for w in filtered if w["state"] not in (".", "_")]
    top_ips = [{"ip": k, "count": v} for k, v in collections.Counter(w["client_ip"] for w in active if w["client_ip"] != "-").most_common(5)]
    top_vhosts = [{"vhost": k, "count": v} for k, v in collections.Counter(w["vhost"] for w in active if w["vhost"] != "-").most_common(5)]
    top_uris = [{"uri": k, "count": v} for k, v in collections.Counter(f"{w['method']} {w['uri']}" for w in active if w["uri"] != "-").most_common(5)]

    bw = metrics["busy_workers"]
    iw = metrics["idle_workers"]
    busy_pct = None
    if bw is not None and iw is not None and (bw + iw) > 0:
        busy_pct = round((bw / float(bw + iw)) * 100.0, 1)

    shown = filtered[:limit_rows] if limit_rows > 0 else filtered
    alert = busy_pct is not None and busy_pct >= warn_busy

    payload = {
        "tool": script_name,
        "version": script_version,
        "timestamp_utc": ts_utc,
        "source": src_label,
        "metrics": {
            "busy_workers": bw,
            "idle_workers": iw,
            "busy_percent": busy_pct,
            "total_accesses": metrics["total_accesses"],
            "req_per_sec": metrics["req_per_sec"],
            "cpu_load": metrics["cpu_load"],
            "uptime": metrics["uptime"],
        },
        "total_workers_parsed": len(workers),
        "filtered_count": len(filtered),
        "shown_count": len(shown),
        "alert_busy_threshold": alert,
        "top_ips": top_ips,
        "top_vhosts": top_vhosts,
        "top_uris": top_uris,
        "workers": shown,
    }

    if fmt == "json":
        print(json.dumps(payload, indent=2))
        return 2 if (exit_code_mode and alert) else 0

    if fmt == "csv":
        buf = io.StringIO()
        w = csv.writer(buf)
        w.writerow(["PID", "STATE", "SS", "CPU", "REQ_MS", "CLIENT_IP", "VHOST", "METHOD", "URI"])
        for r in shown:
            w.writerow([r["pid"], r["state"], r["ss"], r["cpu"], r["req_ms"], r["client_ip"], r["vhost"], r["method"], r["uri"]])
        sys.stdout.write(buf.getvalue())
        return 2 if (exit_code_mode and alert) else 0

    if not quiet:
        print("=" * 98)
        print(f" {c_bold}{script_name} v{script_version}{c_reset} | Source: {src_label} | {ts_utc}")
        print("=" * 98)
        bw_s = str(bw) if bw is not None else "-"
        iw_s = str(iw) if iw is not None else "-"
        bp_s = f"{busy_pct}%" if busy_pct is not None else "-"
        if alert:
            bp_s = f"{c_red}{bp_s}{c_reset}"
        rps_s = str(metrics["req_per_sec"]) if metrics["req_per_sec"] is not None else "-"
        print(f"Workers: Busy={bw_s}  Idle={iw_s}  Busy%={bp_s}  Req/s={rps_s}  Parsed={len(workers)}  Matched={len(filtered)}")

        if top_mode in ("all", "ip") and top_ips:
            print(f"{c_cyan}Top Client IPs:{c_reset} " + " | ".join(f"{x['ip']} ({x['count']})" for x in top_ips))
        if top_mode in ("all", "vhost") and top_vhosts:
            print(f"{c_cyan}Top VHosts:    {c_reset} " + " | ".join(f"{x['vhost']} ({x['count']})" for x in top_vhosts))
        if top_mode in ("all", "uri") and top_uris:
            print(f"{c_cyan}Top Requests:  {c_reset} " + " | ".join(f"{x['uri'][:36]} ({x['count']})" for x in top_uris))
        print("-" * 98)

    if not shown:
        print(f"{c_green}[CLEAN]{c_reset} No matching Apache worker slots.")
    else:
        cols = ["PID", "M", "SS(s)", "CPU", "CLIENT_IP", "VHOST", "REQUEST"]
        rows = []
        for r in shown:
            req_d = f"{r['method']} {r['uri']}" if r["method"] != "-" else r["request"]
            if len(req_d) > 42:
                req_d = req_d[:39] + "..."
            rows.append([r["pid"], r["state"], str(r["ss"]), f"{r['cpu']:.2f}", r["client_ip"], r["vhost"][:26], req_d])
        widths = [len(c) for c in cols]
        for r in rows:
            for i, v in enumerate(r):
                if len(v) > widths[i]:
                    widths[i] = len(v)
        print(f"{c_bold}" + "  ".join(cols[i].ljust(widths[i]) for i in range(len(cols))) + f"{c_reset}")
        print("  ".join("-" * widths[i] for i in range(len(cols))))
        for r in rows:
            print("  ".join(r[i].ljust(widths[i]) for i in range(len(cols))))

    return 2 if (exit_code_mode and alert) else 0


try:
    if watch_sec > 0:
        while True:
            if fmt == "table" and sys.stdout.isatty():
                sys.stdout.write("\033[2J\033[H")
            rc = run_once()
            sys.stdout.flush()
            time.sleep(watch_sec)
    else:
        sys.exit(run_once())
except KeyboardInterrupt:
    sys.exit(0)
except Exception as e:
    print(f"[ERR] {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
)"

  python3 -c "$py_script" \
    "$URL" "$FILE_PATH" "$TIMEOUT_SEC" "$INSECURE" "$AUTH_USER" "$CUSTOM_HEADER" \
    "$METHOD_FILTER" "$VHOST_FILTER" "$IP_FILTER" "$STATE_FILTER" "$SORT_BY" "$LIMIT_ROWS" "$TOP_MODE" \
    "$WATCH_SEC" "$WARN_BUSY" "$EXIT_CODE_MODE" "$OUTPUT_FMT" "$QUIET" \
    "$SCRIPT_NAME" "$SCRIPT_VERSION" \
    "$C_RED" "$C_GREEN" "$C_YELLOW" "$C_CYAN" "$C_BOLD" "$C_RESET"
}

main "$@"
