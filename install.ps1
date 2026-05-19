#Requires -Version 5.1
<#
.SYNOPSIS
    verticalmedia Windows installer
.DESCRIPTION
    Installs verticalmedia on Windows. Requires Python 3.10+ and Git.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$REPO = "https://github.com/PreFounded/verticalmedia.git"
$INSTALL_DIR = Join-Path $env:USERPROFILE "verticalmedia"
$SERVICE_NAME = "verticalmedia"

function Write-Step([string]$msg) {
    Write-Host "`n>> $msg" -ForegroundColor Cyan
}

function Write-OK([string]$msg) {
    Write-Host "   OK  $msg" -ForegroundColor Green
}

function Write-Fail([string]$msg) {
    Write-Host "   FAIL  $msg" -ForegroundColor Red
    exit 1
}

function Prompt-Input([string]$prompt, [string]$default) {
    $val = Read-Host "$prompt [$default]"
    if ([string]::IsNullOrWhiteSpace($val)) { return $default }
    return $val
}

# ── Check Python ──────────────────────────────────────────────────────────────
Write-Step "Checking Python"
try {
    $pyver = python --version 2>&1
    if ($pyver -match "Python (\d+)\.(\d+)") {
        $major = [int]$Matches[1]; $minor = [int]$Matches[2]
        if ($major -lt 3 -or ($major -eq 3 -and $minor -lt 10)) {
            Write-Fail "Python 3.10+ required. Found: $pyver"
        }
        Write-OK $pyver
    } else {
        Write-Fail "Could not parse Python version: $pyver"
    }
} catch {
    Write-Fail "Python not found. Install from https://python.org and re-run."
}

# ── Check Git ─────────────────────────────────────────────────────────────────
Write-Step "Checking Git"
try {
    $gitver = git --version 2>&1
    Write-OK $gitver
} catch {
    Write-Fail "Git not found. Install from https://git-scm.com and re-run."
}

# ── Clone or update ───────────────────────────────────────────────────────────
Write-Step "Installing verticalmedia to $INSTALL_DIR"
if (Test-Path $INSTALL_DIR) {
    Write-Host "   Directory exists — pulling latest..."
    git -C $INSTALL_DIR pull --ff-only
} else {
    git clone $REPO $INSTALL_DIR
}
Write-OK "Files ready"

# ── Virtual environment ───────────────────────────────────────────────────────
Write-Step "Setting up Python environment"
$venv = Join-Path $INSTALL_DIR ".venv"
if (-not (Test-Path $venv)) {
    python -m venv $venv
}
$pip = Join-Path $venv "Scripts\pip.exe"
& $pip install -q --upgrade pip
& $pip install -q -r (Join-Path $INSTALL_DIR "requirements.txt")
Write-OK "Dependencies installed"

# ── Configure .env ────────────────────────────────────────────────────────────
Write-Step "Configuration"
$envFile = Join-Path $INSTALL_DIR ".env"

if (Test-Path $envFile) {
    $overwrite = Read-Host "   .env already exists. Overwrite? [y/N]"
    if ($overwrite -notin @("y", "Y")) {
        Write-Host "   Keeping existing .env"
        goto DONE_ENV
    }
}

$qbitUrl      = Prompt-Input "  qBittorrent URL" "http://localhost:8081"
$qbitUser     = Prompt-Input "  qBittorrent username" "admin"
$qbitPass     = Prompt-Input "  qBittorrent password" "adminadmin"
$prowlarrUrl  = Prompt-Input "  Prowlarr URL (leave blank to skip)" ""
$prowlarrKey  = ""
if ($prowlarrUrl -ne "") {
    $prowlarrKey = Prompt-Input "  Prowlarr API key" ""
}
$pathAnime  = Prompt-Input "  Anime download path" "C:\Downloads\Anime"
$pathMovies = Prompt-Input "  Movies download path" "C:\Downloads\Movies"
$pathShows  = Prompt-Input "  TV shows download path" "C:\Downloads\Shows"

@"
QBIT_URL=$qbitUrl
QBIT_USERNAME=$qbitUser
QBIT_PASSWORD=$qbitPass
PROWLARR_URL=$prowlarrUrl
PROWLARR_KEY=$prowlarrKey
PATH_ANIME=$pathAnime
PATH_MOVIES=$pathMovies
PATH_SHOWS=$pathShows
"@ | Set-Content $envFile -Encoding UTF8
Write-OK ".env written"

:DONE_ENV

# ── Windows service via NSSM (optional) ───────────────────────────────────────
Write-Step "Background service"
$nssm = Get-Command nssm -ErrorAction SilentlyContinue
if ($nssm) {
    $installService = Read-Host "   Install as Windows service via NSSM? [Y/n]"
    if ($installService -notin @("n", "N")) {
        $python = Join-Path $venv "Scripts\python.exe"
        nssm install $SERVICE_NAME $python "-m" "uvicorn" "main:app" "--host" "0.0.0.0" "--port" "7171"
        nssm set $SERVICE_NAME AppDirectory $INSTALL_DIR
        nssm set $SERVICE_NAME AppEnvironmentExtra "DOTENV_PATH=$envFile"
        nssm start $SERVICE_NAME
        Write-OK "Service installed and started"
        Write-Host "`n   Manage with: nssm start|stop|restart $SERVICE_NAME" -ForegroundColor Yellow
    }
} else {
    Write-Host "   NSSM not found — skipping service install" -ForegroundColor Yellow
    $runScript = Join-Path $INSTALL_DIR "run.bat"
    @"
@echo off
cd /d "%~dp0"
call .venv\Scripts\activate.bat
python -m uvicorn main:app --host 0.0.0.0 --port 7171
"@ | Set-Content $runScript -Encoding ASCII
    Write-OK "Created run.bat — double-click to start"
    Write-Host "   For NSSM (run as service): https://nssm.cc" -ForegroundColor Yellow
}

# ── Done ──────────────────────────────────────────────────────────────────────
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host " verticalmedia installed!" -ForegroundColor Green
Write-Host " Open http://localhost:7171 in your browser"
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan
