<#
.SYNOPSIS
    scoreboard.ps1 — Cross-Platform Apache Scoreboard & Worker Auditor CLI (v2.0.0)

.DESCRIPTION
    Clean-room Windows PowerShell 5.1+ / PowerShell 7+ port of scoreboard.sh
    (originally inspired by HostGator's scoreboard, 2011).
    Parses Apache mod_status HTML tables and ?auto metrics over HTTP/HTTPS or
    from saved files, aggregates Top Client IPs / VHosts / Requests, filters
    by method/vhost/ip/state, and emits Table, JSON, or CSV output.

    License: Apache-2.0
    Author:  Percio Castelo (https://perciocastelo.com.br)
    Repo:    https://github.com/sr00t3d/scoreboard
#>

[CmdletBinding()]
param(
    [Alias("u")]
    [string]$Url = "",

    [Alias("f")]
    [string]$File = "",

    [int]$Timeout = 8,

    [Alias("k")]
    [switch]$Insecure,

    [string]$Auth = "",

    [string]$Header = "",

    [string]$Method = "",

    [string]$VHost = "",

    [string]$Ip = "",

    [string]$State = "",

    [ValidateSet("ss", "cpu", "req", "ip", "vhost")]
    [string]$Sort = "ss",

    [int]$Limit = 50,

    [ValidateSet("all", "ip", "vhost", "uri", "none")]
    [string]$Top = "all",

    [int]$Watch = 0,

    [double]$WarnBusy = 90.0,

    [switch]$ExitCode,

    [Alias("o")]
    [ValidateSet("table", "json", "csv")]
    [string]$Output = "table",

    [Alias("q")]
    [switch]$Quiet,

    [Alias("h")]
    [switch]$Help,

    [Alias("v")]
    [switch]$Version
)

$ErrorActionPreference = "Stop"
$ScriptName = "scoreboard.ps1"
$ScriptVersion = "2.0.0"

if ($Version) {
    Write-Output "$ScriptName $ScriptVersion"
    exit 0
}

if ($Help) {
    Write-Output @"
$ScriptName v$ScriptVersion - Apache Scoreboard & Worker Auditor CLI (PowerShell)

Usage:
  .\$ScriptName [-Url <url>] [-File <path>] [options]

Options:
  -Url, -u <url>         Apache server-status URL (default: auto-probe localhost)
  -File, -f <path>       Parse saved mod_status HTML or ?auto file
  -Timeout <sec>         HTTP request timeout in seconds (default: 8)
  -Insecure, -k          Skip TLS certificate validation
  -Auth <user:pass>      HTTP Basic authentication credentials
  -Header <K:V>          Custom HTTP header
  -Method <GET|POST>     Filter workers by HTTP method
  -VHost <substr>        Filter workers by VHost substring
  -Ip <substr>           Filter workers by Client IP substring
  -State <M>             Filter workers by mode char (W, R, K, C, L)
  -Sort <field>          Sort by: ss (default), cpu, req, ip, vhost
  -Limit <N>             Max worker rows (default: 50, 0 = all)
  -Top <mode>            Top summary: all (default), ip, vhost, uri, none
  -Watch <sec>           Refresh continuously every <sec> seconds
  -WarnBusy <pct>        Busy worker % threshold (default: 90)
  -ExitCode              Exit 2 if busy % >= WarnBusy
  -Output, -o <fmt>      table (default), json, csv
  -Quiet, -q             Minimal output
  -Help, -h              Show this help
  -Version, -v           Show version
"@
    exit 0
}

function Strip-Html([string]$s) {
    $t = [regex]::Replace($s, '<[^>]+>', '')
    $t = [System.Net.WebUtility]::HtmlDecode($t)
    return ([regex]::Replace($t, '\s+', ' ')).Trim()
}

function Get-StatusSource {
    if ($File) {
        if (-not (Test-Path -LiteralPath $File)) {
            throw "File not found: $File"
        }
        return @{ Source = $File; Body = (Get-Content -LiteralPath $File -Raw -Encoding UTF8) }
    }

    $candidates = if ($Url) { @($Url) } else {
        @(
            "http://127.0.0.1/whm-server-status",
            "http://127.0.0.1/server-status",
            "http://localhost/whm-server-status",
            "http://localhost/server-status"
        )
    }

    $headers = @{ "User-Agent" = "$ScriptName/$ScriptVersion" }
    if ($Auth -and $Auth.Contains(":")) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Auth)
        $headers["Authorization"] = "Basic " + [Convert]::ToBase64String($bytes)
    }
    if ($Header -and $Header.Contains(":")) {
        $idx = $Header.IndexOf(":")
        $headers[$Header.Substring(0, $idx).Trim()] = $Header.Substring($idx + 1).Trim()
    }

    if ($Insecure -and $PSVersionTable.PSVersion.Major -lt 6) {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    }

    $lastErr = $null
    foreach ($cand in $candidates) {
        try {
            $params = @{
                Uri             = $cand
                Headers         = $headers
                TimeoutSec      = $Timeout
                UseBasicParsing = $true
            }
            if ($Insecure -and $PSVersionTable.PSVersion.Major -ge 6) {
                $params["SkipCertificateCheck"] = $true
            }
            $resp = Invoke-WebRequest @params
            $content = [string]$resp.Content
            if ($content -match 'Apache Server Status|BusyWorkers|Total Accesses|<table|Scoreboard:') {
                return @{ Source = $cand; Body = $content }
            }
        }
        catch {
            $lastErr = $_
        }
    }
    throw "Failed to fetch Apache server-status ($lastErr)"
}

function Parse-ScoreboardBody([string]$RawBody) {
    $metrics = [ordered]@{
        busy_workers   = $null
        idle_workers   = $null
        busy_percent   = $null
        total_accesses = $null
        req_per_sec    = $null
        cpu_load       = $null
        uptime         = $null
    }

    $plain = [System.Net.WebUtility]::HtmlDecode([regex]::Replace($RawBody, '<[^>]+>', "`n"))
    foreach ($ln in ($plain -split "`r?`n")) {
        $line = $ln.Trim()
        if (-not $line) { continue }
        if ($line -match '^(\d+)\s+requests currently being processed,\s+(\d+)\s+idle workers') {
            $metrics.busy_workers = [int]$matches[1]
            $metrics.idle_workers = [int]$matches[2]
        }
        elseif ($line -match '^BusyWorkers:\s*(\d+)') { $metrics.busy_workers = [int]$matches[1] }
        elseif ($line -match '^IdleWorkers:\s*(\d+)') { $metrics.idle_workers = [int]$matches[1] }
        elseif ($line -match '^Total Accesses:\s*(\d+)') { $metrics.total_accesses = [int]$matches[1] }
        elseif ($line -match '^ReqPerSec:\s*([0-9.]+)') { $metrics.req_per_sec = [double]$matches[1] }
        elseif ($line -match '^CPULoad:\s*([0-9.]+)') { $metrics.cpu_load = [double]$matches[1] }
        elseif ($line -match '^Server uptime:\s*(.+)$') { $metrics.uptime = $matches[1].Trim() }
        elseif ($line -match '([0-9.]+)\s+requests/sec' -and $null -eq $metrics.req_per_sec) {
            $metrics.req_per_sec = [double]$matches[1]
        }
    }

    if ($null -ne $metrics.busy_workers -and $null -ne $metrics.idle_workers -and ($metrics.busy_workers + $metrics.idle_workers) -gt 0) {
        $metrics.busy_percent = [math]::Round(($metrics.busy_workers / ($metrics.busy_workers + $metrics.idle_workers)) * 100.0, 1)
    }

    $workers = New-Object System.Collections.Generic.List[object]
    $tableMatches = [regex]::Matches($RawBody, '(?is)<table[^>]*>(.*?)</table>')
    foreach ($tm in $tableMatches) {
        $rowMatches = [regex]::Matches($tm.Groups[1].Value, '(?is)<tr[^>]*>(.*?)</tr>')
        if ($rowMatches.Count -lt 2) { continue }

        $hdrCells = [regex]::Matches($rowMatches[0].Groups[1].Value, '(?is)<t[hd][^>]*>(.*?)</t[hd]>')
        $hdrs = @()
        $colMap = @{}
        for ($i = 0; $i -lt $hdrCells.Count; $i++) {
            $h = (Strip-Html $hdrCells[$i].Groups[1].Value).ToLower()
            $hdrs += $h
            if (-not $colMap.ContainsKey($h)) { $colMap[$h] = $i }
        }
        if (-not ($colMap.ContainsKey("client") -or $colMap.ContainsKey("vhost") -or $colMap.ContainsKey("request") -or $colMap.ContainsKey("pid"))) {
            continue
        }

        for ($r = 1; $r -lt $rowMatches.Count; $r++) {
            $rowHtml = $rowMatches[$r].Groups[1].Value
            if ($rowHtml -match '(?is)<th\b' -and $rowHtml -notmatch '(?is)<td\b') { continue }
            $cells = [regex]::Matches($rowHtml, '(?is)<t[hd][^>]*>(.*?)</t[hd]>')
            $vals = @()
            foreach ($c in $cells) { $vals += (Strip-Html $c.Groups[1].Value) }

            $getCol = {
                param([string]$name)
                if ($colMap.ContainsKey($name) -and $colMap[$name] -lt $vals.Count) { return $vals[$colMap[$name]] }
                return ""
            }

            $pidVal = & $getCol "pid"
            $modeVal = & $getCol "m"
            $cpuRaw = & $getCol "cpu"
            $ssRaw = & $getCol "ss"
            $reqRaw = & $getCol "req"
            $clientVal = & $getCol "client"
            $vhostVal = & $getCol "vhost"
            $reqVal = & $getCol "request"

            $cpuNum = 0.0; [void][double]::TryParse(($cpuRaw -replace '[^0-9.-]', ''), [ref]$cpuNum)
            $ssNum = 0; [void][int]::TryParse(($ssRaw -replace '[^0-9-]', ''), [ref]$ssNum)
            $reqNum = 0; [void][int]::TryParse(($reqRaw -replace '[^0-9-]', ''), [ref]$reqNum)

            $meth = "-"
            $uri = if ($reqVal) { $reqVal } else { "-" }
            if ($reqVal -match '^([A-Z]+)\s+(\S+)') {
                $meth = $matches[1]
                $uri = $matches[2]
            }

            $workers.Add([PSCustomObject]@{
                pid       = if ($pidVal) { $pidVal } else { "-" }
                state     = if ($modeVal) { $modeVal } else { "-" }
                cpu       = $cpuNum
                ss        = $ssNum
                req_ms    = $reqNum
                client_ip = if ($clientVal) { $clientVal } else { "-" }
                vhost     = if ($vhostVal) { $vhostVal } else { "-" }
                method    = $meth
                uri       = $uri
                request   = if ($reqVal) { $reqVal } else { "-" }
            })
        }
    }

    return @{ Metrics = $metrics; Workers = $workers }
}

function Invoke-ScoreboardOnce {
    $tsUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $src = Get-StatusSource
    $parsed = Parse-ScoreboardBody $src.Body
    $metrics = $parsed.Metrics
    $allWorkers = $parsed.Workers

    $filtered = @($allWorkers | Where-Object {
        ($Method -eq "" -or $_.method.ToUpper() -eq $Method.ToUpper()) -and
        ($VHost -eq "" -or $_.vhost.ToLower().Contains($VHost.ToLower())) -and
        ($Ip -eq "" -or $_.client_ip.Contains($Ip)) -and
        ($State -eq "" -or $_.state.ToUpper() -eq $State.ToUpper())
    })

    $sorted = switch ($Sort) {
        "ss"    { @($filtered | Sort-Object -Property @{Expression="ss"; Descending=$true}, @{Expression="cpu"; Descending=$true}) }
        "cpu"   { @($filtered | Sort-Object -Property @{Expression="cpu"; Descending=$true}, @{Expression="ss"; Descending=$true}) }
        "req"   { @($filtered | Sort-Object -Property @{Expression="req_ms"; Descending=$true}, @{Expression="ss"; Descending=$true}) }
        "ip"    { @($filtered | Sort-Object -Property @{Expression="client_ip"; Descending=$false}, @{Expression="ss"; Descending=$true}) }
        "vhost" { @($filtered | Sort-Object -Property @{Expression="vhost"; Descending=$false}, @{Expression="ss"; Descending=$true}) }
    }

    $active = @($sorted | Where-Object { $_.state -notin @(".", "_") })
    $topIps = @($active | Where-Object { $_.client_ip -ne "-" } | Group-Object client_ip | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object { @{ ip = $_.Name; count = $_.Count } })
    $topVHosts = @($active | Where-Object { $_.vhost -ne "-" } | Group-Object vhost | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object { @{ vhost = $_.Name; count = $_.Count } })
    $topUris = @($active | Where-Object { $_.uri -ne "-" } | ForEach-Object { "$($_.method) $($_.uri)" } | Group-Object | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object { @{ uri = $_.Name; count = $_.Count } })

    $shown = if ($Limit -gt 0 -and $sorted.Count -gt $Limit) { @($sorted | Select-Object -First $Limit) } else { $sorted }
    $alert = ($null -ne $metrics.busy_percent -and $metrics.busy_percent -ge $WarnBusy)

    $payload = [ordered]@{
        tool                 = $ScriptName
        version              = $ScriptVersion
        timestamp_utc        = $tsUtc
        source               = $src.Source
        metrics              = $metrics
        total_workers_parsed = $allWorkers.Count
        filtered_count       = $sorted.Count
        shown_count          = $shown.Count
        alert_busy_threshold = $alert
        top_ips              = $topIps
        top_vhosts           = $topVHosts
        top_uris             = $topUris
        workers              = $shown
    }

    if ($Output -eq "json") {
        $payload | ConvertTo-Json -Depth 6
        $script:FinalExitCode = if ($ExitCode -and $alert) { 2 } else { 0 }
        return
    }

    if ($Output -eq "csv") {
        $shown | Select-Object @{N="PID";E={$_.pid}}, @{N="STATE";E={$_.state}}, @{N="SS";E={$_.ss}}, @{N="CPU";E={$_.cpu}}, @{N="REQ_MS";E={$_.req_ms}}, @{N="CLIENT_IP";E={$_.client_ip}}, @{N="VHOST";E={$_.vhost}}, @{N="METHOD";E={$_.method}}, @{N="URI";E={$_.uri}} | ConvertTo-Csv -NoTypeInformation
        $script:FinalExitCode = if ($ExitCode -and $alert) { 2 } else { 0 }
        return
    }

    if (-not $Quiet) {
        Write-Output ("=" * 98)
        Write-Output " $ScriptName v$ScriptVersion | Source: $($src.Source) | $tsUtc"
        Write-Output ("=" * 98)
        $bwS = if ($null -ne $metrics.busy_workers) { $metrics.busy_workers } else { "-" }
        $iwS = if ($null -ne $metrics.idle_workers) { $metrics.idle_workers } else { "-" }
        $bpS = if ($null -ne $metrics.busy_percent) { "$($metrics.busy_percent)%" } else { "-" }
        $rpsS = if ($null -ne $metrics.req_per_sec) { $metrics.req_per_sec } else { "-" }
        Write-Output "Workers: Busy=$bwS  Idle=$iwS  Busy%=$bpS  Req/s=$rpsS  Parsed=$($allWorkers.Count)  Matched=$($sorted.Count)"
        if ($Top -in @("all", "ip") -and $topIps.Count -gt 0) {
            Write-Output ("Top Client IPs: " + (($topIps | ForEach-Object { "$($_.ip) ($($_.count))" }) -join " | "))
        }
        if ($Top -in @("all", "vhost") -and $topVHosts.Count -gt 0) {
            Write-Output ("Top VHosts:     " + (($topVHosts | ForEach-Object { "$($_.vhost) ($($_.count))" }) -join " | "))
        }
        if ($Top -in @("all", "uri") -and $topUris.Count -gt 0) {
            Write-Output ("Top Requests:   " + (($topUris | ForEach-Object { "$($_.uri) ($($_.count))" }) -join " | "))
        }
        Write-Output ("-" * 98)
    }

    if ($shown.Count -eq 0) {
        Write-Output "[CLEAN] No matching Apache worker slots."
    }
    else {
        $shown | Format-Table -AutoSize @(
            @{Label="PID"; Expression={$_.pid}},
            @{Label="M"; Expression={$_.state}},
            @{Label="SS(s)"; Expression={$_.ss}},
            @{Label="CPU"; Expression={"{0:N2}" -f $_.cpu}},
            @{Label="CLIENT_IP"; Expression={$_.client_ip}},
            @{Label="VHOST"; Expression={$_.vhost}},
            @{Label="REQUEST"; Expression={ if ($_.method -ne "-") { "$($_.method) $($_.uri)" } else { $_.request } }}
        ) | Out-String -Width 160 | ForEach-Object { $_.TrimEnd() } | Write-Output
    }

    $script:FinalExitCode = if ($ExitCode -and $alert) { 2 } else { 0 }
}

$script:FinalExitCode = 0
try {
    if ($Watch -gt 0) {
        while ($true) {
            if ($Output -eq "table") { try { Clear-Host } catch {} }
            Invoke-ScoreboardOnce
            Start-Sleep -Seconds $Watch
        }
    }
    else {
        Invoke-ScoreboardOnce
        exit $script:FinalExitCode
    }
}
catch {
    [Console]::Error.WriteLine("[ERR] $($_.Exception.Message)")
    exit 1
}
