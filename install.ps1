#Requires -Version 5.1
<#
.SYNOPSIS
    verticalmedia Windows installer
.DESCRIPTION
    Interactive installer for verticalmedia on Windows.
    Requires Python 3.10+ and Git.
.EXAMPLE
    irm https://raw.githubusercontent.com/PreFounded/verticalmedia/main/install.ps1 | iex
#>

$ErrorActionPreference = "Stop"
$REPO = "https://github.com/PreFounded/verticalmedia.git"

# ─────────────────────────────────────────────────────────────────────────────
#  Helpers
# ─────────────────────────────────────────────────────────────────────────────

function header {
    Clear-Host
    Write-Host ""
    Write-Host "  ██╗   ██╗███╗   ███╗" -ForegroundColor Cyan
    Write-Host "  ██║   ██║████╗ ████║" -ForegroundColor Cyan
    Write-Host "  ██║   ██║██╔████╔██║" -ForegroundColor Cyan
    Write-Host "  ╚██╗ ██╔╝██║╚██╔╝██║" -ForegroundColor Cyan
    Write-Host "   ╚████╔╝ ██║ ╚═╝ ██║" -ForegroundColor Cyan
    Write-Host "    ╚═══╝  ╚═╝     ╚═╝  " -NoNewline -ForegroundColor Cyan
    Write-Host "verticalmedia installer" -ForegroundColor White
    Write-Host ""
}

function section([string]$title) {
    Write-Host ""
    Write-Host "  ── $title " -ForegroundColor Cyan -NoNewline
    Write-Host ("─" * [Math]::Max(2, 44 - $title.Length)) -ForegroundColor DarkGray
}

function ok([string]$msg)   { Write-Host "  ✓  $msg" -ForegroundColor Green }
function info([string]$msg) { Write-Host "     $msg" -ForegroundColor DarkGray }
function warn([string]$msg) { Write-Host "  !  $msg" -ForegroundColor Yellow }

function die([string]$msg) {
    Write-Host ""
    Write-Host "  ✗  $msg" -ForegroundColor Red
    Write-Host ""
    exit 1
}

function ask([string]$prompt, [string]$default = "") {
    if ($default -ne "") {
        Write-Host "     $prompt" -ForegroundColor White -NoNewline
        Write-Host " [$default]" -ForegroundColor DarkGray -NoNewline
        Write-Host ": " -NoNewline
    } else {
        Write-Host "     ${prompt}: " -ForegroundColor White -NoNewline
    }
    $val = Read-Host
    if ([string]::IsNullOrWhiteSpace($val)) { return $default }
    return $val.Trim()
}

function askYN([string]$prompt, [bool]$defaultYes = $true) {
    $hint = if ($defaultYes) { "Y/n" } else { "y/N" }
    Write-Host "     $prompt " -ForegroundColor White -NoNewline
    Write-Host "[$hint]" -ForegroundColor DarkGray -NoNewline
    Write-Host ": " -NoNewline
    $val = (Read-Host).Trim().ToLower()
    if ($val -eq "") { return $defaultYes }
    return $val -eq "y"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Step 1 — Check dependencies
# ─────────────────────────────────────────────────────────────────────────────

header
section "Checking requirements"

# Python
try {
    $pyraw = python --version 2>&1
    if ($pyraw -match "Python (\d+)\.(\d+)") {
        $maj = [int]$Matches[1]; $min = [int]$Matches[2]
        if ($maj -lt 3 -or ($maj -eq 3 -and $min -lt 10)) {
            die "Python 3.10+ required (found $pyraw). Download: https://python.org/downloads"
        }
        ok $pyraw
    } else { die "Could not detect Python version. Install Python 3.10+ from https://python.org/downloads" }
} catch { die "Python not found. Install Python 3.10+ from https://python.org/downloads — tick 'Add to PATH'" }

# Git
try {
    $gitraw = git --version 2>&1
    ok $gitraw
} catch { die "Git not found. Install from https://git-scm.com/download/win" }

# ─────────────────────────────────────────────────────────────────────────────
#  Step 2 — Install location
# ─────────────────────────────────────────────────────────────────────────────

section "Install location"

$defaultDir = Join-Path $env:USERPROFILE "verticalmedia"
$installDir = ask "Where should verticalmedia be installed?" $defaultDir

if (Test-Path $installDir) {
    warn "Folder already exists — will pull latest updates instead of a fresh clone."
} else {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}

info "Installing to: $installDir"

# ─────────────────────────────────────────────────────────────────────────────
#  Step 3 — Clone / update
# ─────────────────────────────────────────────────────────────────────────────

section "Downloading files"

if (Test-Path (Join-Path $installDir ".git")) {
    info "Updating existing installation..."
    git -C $installDir pull --ff-only 2>&1 | ForEach-Object { info $_ }
} else {
    info "Cloning repository..."
    git clone $REPO $installDir 2>&1 | ForEach-Object { info $_ }
}
ok "Files ready"

# ─────────────────────────────────────────────────────────────────────────────
#  Step 4 — Python environment
# ─────────────────────────────────────────────────────────────────────────────

section "Python environment"

$venv   = Join-Path $installDir ".venv"
$python = Join-Path $venv "Scripts\python.exe"
$pip    = Join-Path $venv "Scripts\pip.exe"

if (-not (Test-Path $venv)) {
    info "Creating virtual environment..."
    python -m venv $venv
}

info "Installing dependencies..."
& $pip install -q --upgrade pip
& $pip install -q -r (Join-Path $installDir "requirements.txt")
ok "Dependencies installed"

# ─────────────────────────────────────────────────────────────────────────────
#  Step 5 — Configuration
# ─────────────────────────────────────────────────────────────────────────────

$envFile    = Join-Path $installDir ".env"
$configEnv  = $true

if (Test-Path $envFile) {
    section "Existing configuration found"
    $configEnv = askYN "Reconfigure settings?" $false
}

if ($configEnv) {
    section "qBittorrent"
    info "verticalmedia sends torrents to qBittorrent. Make sure its Web UI is enabled."
    info "(qBittorrent → Preferences → Web UI → Enable Web UI)"
    Write-Host ""
    $qbitUrl  = ask "qBittorrent Web UI URL"  "http://localhost:8081"
    $qbitUser = ask "qBittorrent username"    "admin"
    $qbitPass = ask "qBittorrent password"    "adminadmin"

    section "Prowlarr (optional)"
    info "Prowlarr is an indexer manager that gives access to many more torrent sources."
    info "Skip this if you don't use Prowlarr — you can add it later via the settings panel."
    Write-Host ""
    $useProwlarr = askYN "Do you use Prowlarr?" $false
    $prowlarrUrl = ""
    $prowlarrKey = ""
    if ($useProwlarr) {
        $prowlarrUrl = ask "Prowlarr URL"    "http://localhost:9696"
        $prowlarrKey = ask "Prowlarr API key" ""
    }

    section "Download paths"
    info "Where should torrents be saved? Use full Windows paths (e.g. D:\Media\Anime)."
    info "These must match the save paths configured in qBittorrent's category settings."
    Write-Host ""
    $pathAnime  = ask "Anime save path"    "C:\Downloads\Anime"
    $pathMovies = ask "Movies save path"   "C:\Downloads\Movies"
    $pathShows  = ask "TV shows save path" "C:\Downloads\Shows"

    section "Server"
    $vmPort = ask "Port to run on" "7171"

    # Write .env
    @"
# qBittorrent
QBIT_URL=$qbitUrl
QBIT_USERNAME=$qbitUser
QBIT_PASSWORD=$qbitPass

# Prowlarr (leave KEY empty to disable)
PROWLARR_URL=$prowlarrUrl
PROWLARR_KEY=$prowlarrKey

# Download paths
PATH_ANIME=$pathAnime
PATH_MOVIES=$pathMovies
PATH_SHOWS=$pathShows

# Server
VM_PORT=$vmPort
VM_HOST=0.0.0.0
"@ | Set-Content $envFile -Encoding UTF8
    ok ".env saved to $envFile"
} else {
    info "Keeping existing configuration."
    # Read port from existing .env for the done message
    $vmPort = "7171"
    if (Test-Path $envFile) {
        $portLine = Get-Content $envFile | Where-Object { $_ -match "^VM_PORT=" }
        if ($portLine) { $vmPort = $portLine -replace "^VM_PORT=", "" }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  Step 6 — Always write run.bat
# ─────────────────────────────────────────────────────────────────────────────

$runBat = Join-Path $installDir "run.bat"
@"
@echo off
title verticalmedia
cd /d "%~dp0"
call .venv\Scripts\activate.bat
python -m uvicorn main:app --host 0.0.0.0 --port %VM_PORT%
pause
"@ | Set-Content $runBat -Encoding ASCII

# ─────────────────────────────────────────────────────────────────────────────
#  Step 7 — Background service (optional)
# ─────────────────────────────────────────────────────────────────────────────

section "Run on startup (optional)"
info "Without a service, use run.bat to start verticalmedia manually."
Write-Host ""

$nssm = Get-Command nssm -ErrorAction SilentlyContinue
$schtasks = Get-Command schtasks -ErrorAction SilentlyContinue

if ($nssm) {
    $installService = askYN "Install as a Windows service (auto-start, runs in background)?" $true
    if ($installService) {
        $svcName = "verticalmedia"
        # Remove existing service if present
        $existing = nssm status $svcName 2>&1
        if ($existing -notmatch "No such service") {
            info "Removing existing service..."
            nssm stop $svcName 2>&1 | Out-Null
            nssm remove $svcName confirm 2>&1 | Out-Null
        }
        nssm install $svcName $python "-m" "uvicorn" "main:app" "--host" "0.0.0.0" "--port" $vmPort
        nssm set $svcName AppDirectory $installDir
        nssm set $svcName AppEnvironmentExtra "@$envFile"
        nssm set $svcName Start SERVICE_AUTO_START
        nssm start $svcName
        ok "Service installed and started (auto-starts with Windows)"
        info "Manage: nssm start|stop|restart verticalmedia"
    } else {
        ok "Skipped. Use run.bat to start manually."
    }
} elseif ($schtasks) {
    $useScheduler = askYN "Register as a startup task (runs at login, no NSSM needed)?" $true
    if ($useScheduler) {
        $taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers><LogonTrigger><Enabled>true</Enabled></LogonTrigger></Triggers>
  <Settings><ExecutionTimeLimit>PT0S</ExecutionTimeLimit><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy></Settings>
  <Actions><Exec>
    <Command>$python</Command>
    <Arguments>-m uvicorn main:app --host 0.0.0.0 --port $vmPort</Arguments>
    <WorkingDirectory>$installDir</WorkingDirectory>
  </Exec></Actions>
</Task>
"@
        $xmlPath = Join-Path $env:TEMP "verticalmedia-task.xml"
        [System.IO.File]::WriteAllText($xmlPath, $taskXml, [System.Text.Encoding]::Unicode)
        schtasks /Create /TN "verticalmedia" /XML $xmlPath /F | Out-Null
        Remove-Item $xmlPath -Force
        ok "Startup task registered (runs at login)"
        info "Manage: Task Scheduler → verticalmedia"
    } else {
        ok "Skipped. Use run.bat to start manually."
    }
} else {
    warn "Neither NSSM nor Task Scheduler found — using run.bat only."
    info "For auto-start: install NSSM from https://nssm.cc and re-run this installer."
    ok "run.bat created — double-click to start verticalmedia"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Done
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  ──────────────────────────────────────────────" -ForegroundColor Cyan
Write-Host "   verticalmedia is ready!" -ForegroundColor Green
Write-Host ""
Write-Host "   Open: " -NoNewline -ForegroundColor DarkGray
Write-Host "http://localhost:$vmPort" -ForegroundColor Cyan
Write-Host "   Docs: " -NoNewline -ForegroundColor DarkGray
Write-Host "http://localhost:$vmPort/docs" -ForegroundColor DarkGray
Write-Host ""
Write-Host "   Config: $envFile" -ForegroundColor DarkGray
Write-Host "   Run:    $runBat" -ForegroundColor DarkGray
Write-Host "  ──────────────────────────────────────────────" -ForegroundColor Cyan
Write-Host ""
