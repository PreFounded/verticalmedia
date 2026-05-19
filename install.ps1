#Requires -Version 5.1
<#
.SYNOPSIS
    verticalmedia Windows installer
.DESCRIPTION
    Fully self-contained installer for verticalmedia on Windows.
    Automatically installs Python and Git if missing.
.EXAMPLE
    irm https://raw.githubusercontent.com/PreFounded/verticalmedia/main/install.ps1 | iex
#>

$ErrorActionPreference = "Stop"
$REPO        = "https://github.com/PreFounded/verticalmedia.git"
$PY_VERSION  = "3.12.7"
$PY_URL      = "https://www.python.org/ftp/python/$PY_VERSION/python-$PY_VERSION-amd64.exe"

# ─────────────────────────────────────────────────────────────────────────────
#  Helpers
# ─────────────────────────────────────────────────────────────────────────────

function Show-Header {
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

function Show-Section([string]$title) {
    Write-Host ""
    Write-Host "  ── $title " -ForegroundColor Cyan -NoNewline
    Write-Host ("─" * [Math]::Max(2, 44 - $title.Length)) -ForegroundColor DarkGray
}

function Write-Ok([string]$msg)   { Write-Host "  v  $msg" -ForegroundColor Green }
function Write-Info([string]$msg) { Write-Host "     $msg" -ForegroundColor DarkGray }
function Write-Warn([string]$msg) { Write-Host "  !  $msg" -ForegroundColor Yellow }

function Stop-Install([string]$msg) {
    Write-Host ""
    Write-Host "  x  $msg" -ForegroundColor Red
    Write-Host ""
    exit 1
}

function Read-Input([string]$prompt, [string]$default = "") {
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

function Read-YN([string]$prompt, [bool]$defaultYes = $true) {
    $hint = if ($defaultYes) { "Y/n" } else { "y/N" }
    Write-Host "     $prompt " -ForegroundColor White -NoNewline
    Write-Host "[$hint]" -ForegroundColor DarkGray -NoNewline
    Write-Host ": " -NoNewline
    $val = (Read-Host).Trim().ToLower()
    if ($val -eq "") { return $defaultYes }
    return $val -eq "y"
}

function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
}

function Download-File([string]$url, [string]$dest) {
    Write-Info "Downloading $(Split-Path $url -Leaf)..."
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile($url, $dest)
}

# ─────────────────────────────────────────────────────────────────────────────
#  Dependency installers
# ─────────────────────────────────────────────────────────────────────────────

function Install-Python {
    Show-Section "Installing Python $PY_VERSION"

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Info "Using winget..."
        winget install --id Python.Python.3.12 --source winget `
            --accept-package-agreements --accept-source-agreements -e --silent
        Refresh-Path
    } else {
        $installer = Join-Path $env:TEMP "python-installer.exe"
        Download-File $PY_URL $installer
        Write-Info "Running Python installer silently..."
        $args = "/quiet InstallAllUsers=0 PrependPath=1 Include_launcher=0 Include_test=0"
        Start-Process -FilePath $installer -ArgumentList $args -Wait
        Remove-Item $installer -Force
        Refresh-Path
    }

    # Verify
    try {
        $v = python --version 2>&1
        Write-Ok "Python installed: $v"
    } catch {
        Stop-Install "Python installation failed. Install manually from https://python.org/downloads — tick 'Add to PATH'."
    }
}

function Install-Git {
    Show-Section "Installing Git"

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Info "Using winget..."
        winget install --id Git.Git --source winget `
            --accept-package-agreements --accept-source-agreements -e --silent
        Refresh-Path
    } else {
        Write-Info "Fetching latest Git for Windows release..."
        try {
            $release = Invoke-RestMethod "https://api.github.com/repos/git-for-windows/git/releases/latest"
            $asset   = $release.assets | Where-Object { $_.name -match "64-bit\.exe$" } | Select-Object -First 1
            $gitUrl  = $asset.browser_download_url
        } catch {
            Stop-Install "Could not fetch Git release info. Install manually from https://git-scm.com/download/win"
        }
        $installer = Join-Path $env:TEMP "git-installer.exe"
        Download-File $gitUrl $installer
        Write-Info "Running Git installer silently..."
        $args = "/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /COMPONENTS=`"icons,ext\reg\shellhere,assoc,assoc_sh`""
        Start-Process -FilePath $installer -ArgumentList $args -Wait
        Remove-Item $installer -Force
        Refresh-Path
    }

    # Verify
    try {
        $v = git --version 2>&1
        Write-Ok "Git installed: $v"
    } catch {
        Stop-Install "Git installation failed. Install manually from https://git-scm.com/download/win"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  Step 1 — Requirements (auto-install if missing)
# ─────────────────────────────────────────────────────────────────────────────

Show-Header
Show-Section "Requirements"

# Python
$pythonOk = $false
try {
    $pyraw = python --version 2>&1
    if ($pyraw -match "Python (\d+)\.(\d+)") {
        $maj = [int]$Matches[1]; $min = [int]$Matches[2]
        if ($maj -gt 3 -or ($maj -eq 3 -and $min -ge 10)) {
            Write-Ok $pyraw
            $pythonOk = $true
        } else {
            Write-Warn "Found $pyraw but 3.10+ is required — will install a newer version."
        }
    }
} catch {
    Write-Warn "Python not found — will install automatically."
}
if (-not $pythonOk) { Install-Python }

# Git
$gitOk = $false
try {
    $gitraw = git --version 2>&1
    Write-Ok $gitraw
    $gitOk = $true
} catch {
    Write-Warn "Git not found — will install automatically."
}
if (-not $gitOk) { Install-Git }

# ─────────────────────────────────────────────────────────────────────────────
#  Step 2 — Install location
# ─────────────────────────────────────────────────────────────────────────────

Show-Section "Install location"

$defaultDir = Join-Path $env:USERPROFILE "verticalmedia"
$installDir = Read-Input "Where should verticalmedia be installed?" $defaultDir

if (Test-Path (Join-Path $installDir ".git")) {
    Write-Warn "Existing installation found — will update to latest."
} elseif (Test-Path $installDir) {
    Write-Warn "Folder exists but is not a git repo — files may be overwritten."
} else {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}

Write-Info "Location: $installDir"

# ─────────────────────────────────────────────────────────────────────────────
#  Step 3 — Clone / update
# ─────────────────────────────────────────────────────────────────────────────

Show-Section "Downloading verticalmedia"

if (Test-Path (Join-Path $installDir ".git")) {
    Write-Info "Pulling latest changes..."
    git -C $installDir pull --ff-only 2>&1 | ForEach-Object { Write-Info $_ }
} else {
    Write-Info "Cloning repository..."
    git clone $REPO $installDir 2>&1 | ForEach-Object { Write-Info $_ }
}
Write-Ok "Files ready"

# ─────────────────────────────────────────────────────────────────────────────
#  Step 4 — Python virtual environment + deps
# ─────────────────────────────────────────────────────────────────────────────

Show-Section "Python environment"

$venv   = Join-Path $installDir ".venv"
$pyExe  = Join-Path $venv "Scripts\python.exe"
$pipExe = Join-Path $venv "Scripts\pip.exe"

if (-not (Test-Path $venv)) {
    Write-Info "Creating virtual environment..."
    python -m venv $venv
}

Write-Info "Installing dependencies (this takes a moment)..."
& $pipExe install -q --upgrade pip
& $pipExe install -q -r (Join-Path $installDir "requirements.txt")
Write-Ok "Dependencies installed"

# ─────────────────────────────────────────────────────────────────────────────
#  Step 5 — Configuration
# ─────────────────────────────────────────────────────────────────────────────

$envFile   = Join-Path $installDir ".env"
$doConfig  = $true

if (Test-Path $envFile) {
    Show-Section "Existing configuration found"
    $doConfig = Read-YN "Reconfigure settings?" $false
}

if ($doConfig) {
    Show-Section "qBittorrent"
    Write-Info "verticalmedia sends torrents directly to qBittorrent."
    Write-Info "Enable its Web UI first: qBittorrent > Preferences > Web UI > Enable Web UI"
    Write-Host ""
    $qbitUrl  = Read-Input "qBittorrent Web UI URL"  "http://localhost:8081"
    $qbitUser = Read-Input "qBittorrent username"    "admin"
    $qbitPass = Read-Input "qBittorrent password"    "adminadmin"

    Show-Section "Prowlarr (optional)"
    Write-Info "Prowlarr aggregates many torrent indexers into one API."
    Write-Info "Skip this if you don't use it — it can be added later in Settings."
    Write-Host ""
    $useProwlarr = Read-YN "Do you use Prowlarr?" $false
    $prowlarrUrl = ""; $prowlarrKey = ""
    if ($useProwlarr) {
        $prowlarrUrl = Read-Input "Prowlarr URL"     "http://localhost:9696"
        $prowlarrKey = Read-Input "Prowlarr API key" ""
    }

    Show-Section "Download paths"
    Write-Info "Full Windows paths for where torrents will be saved."
    Write-Info "These must match the category save paths in qBittorrent."
    Write-Host ""
    $pathAnime  = Read-Input "Anime save path"    "C:\Downloads\Anime"
    $pathMovies = Read-Input "Movies save path"   "C:\Downloads\Movies"
    $pathShows  = Read-Input "TV shows save path" "C:\Downloads\Shows"

    Show-Section "Server settings"
    $vmPort = Read-Input "Port to listen on" "7171"

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
VM_HOST=0.0.0.0
VM_PORT=$vmPort
"@ | Set-Content $envFile -Encoding UTF8
    Write-Ok ".env written to $envFile"

} else {
    Write-Info "Keeping existing configuration."
    $vmPort = "7171"
    $portLine = Get-Content $envFile -ErrorAction SilentlyContinue |
                Where-Object { $_ -match "^VM_PORT=" } |
                Select-Object -First 1
    if ($portLine) { $vmPort = $portLine -replace "^VM_PORT=\s*", "" }
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
python -m uvicorn main:app --host 0.0.0.0 --port $vmPort
pause
"@ | Set-Content $runBat -Encoding ASCII

# ─────────────────────────────────────────────────────────────────────────────
#  Step 7 — Run on startup (optional)
# ─────────────────────────────────────────────────────────────────────────────

Show-Section "Run on startup (optional)"
Write-Info "Without a service, double-click run.bat to start verticalmedia."
Write-Host ""

$nssm     = Get-Command nssm -ErrorAction SilentlyContinue
$schtasks = Get-Command schtasks -ErrorAction SilentlyContinue

if ($nssm) {
    if (Read-YN "Install as a Windows service via NSSM? (runs in background, auto-starts with Windows)" $true) {
        $svcName = "verticalmedia"
        $existing = nssm status $svcName 2>&1
        if ($LASTEXITCODE -eq 0 -and $existing -notmatch "No such service") {
            Write-Info "Removing previous service..."
            nssm stop $svcName 2>&1 | Out-Null
            nssm remove $svcName confirm 2>&1 | Out-Null
        }
        nssm install $svcName $pyExe "-m" "uvicorn" "main:app" "--host" "0.0.0.0" "--port" $vmPort
        nssm set $svcName AppDirectory $installDir
        nssm set $svcName AppEnvironmentExtra "@$envFile"
        nssm set $svcName Start SERVICE_AUTO_START
        nssm start $svcName
        Write-Ok "Service installed and started (auto-starts with Windows)"
        Write-Info "Manage: nssm start|stop|restart verticalmedia"
    } else {
        Write-Ok "Skipped — use run.bat to start manually."
    }
} elseif ($schtasks) {
    if (Read-YN "Register as a login startup task via Task Scheduler?" $true) {
        $taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers><LogonTrigger><Enabled>true</Enabled></LogonTrigger></Triggers>
  <Settings>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <Hidden>true</Hidden>
  </Settings>
  <Actions><Exec>
    <Command>$pyExe</Command>
    <Arguments>-m uvicorn main:app --host 0.0.0.0 --port $vmPort</Arguments>
    <WorkingDirectory>$installDir</WorkingDirectory>
  </Exec></Actions>
</Task>
"@
        $xmlPath = Join-Path $env:TEMP "verticalmedia-task.xml"
        [System.IO.File]::WriteAllText($xmlPath, $taskXml, [System.Text.Encoding]::Unicode)
        schtasks /Create /TN "verticalmedia" /XML $xmlPath /F | Out-Null
        Remove-Item $xmlPath -Force
        Write-Ok "Startup task registered — verticalmedia launches at login"
        Write-Info "Manage: Task Scheduler > verticalmedia"
    } else {
        Write-Ok "Skipped — use run.bat to start manually."
    }
} else {
    Write-Warn "Service setup skipped (NSSM not found)."
    Write-Info "To auto-start on boot: install NSSM from https://nssm.cc and re-run this script."
    Write-Ok "run.bat written — double-click it to start verticalmedia"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Done
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  ──────────────────────────────────────────────" -ForegroundColor Cyan
Write-Host "   verticalmedia is ready!" -ForegroundColor Green
Write-Host ""
Write-Host "   Open  > " -NoNewline -ForegroundColor DarkGray
Write-Host "http://localhost:$vmPort" -ForegroundColor Cyan
Write-Host "   API   > " -NoNewline -ForegroundColor DarkGray
Write-Host "http://localhost:$vmPort/docs" -ForegroundColor DarkGray
Write-Host ""
Write-Host "   Config : $envFile" -ForegroundColor DarkGray
Write-Host "   Run    : $runBat" -ForegroundColor DarkGray
Write-Host "  ──────────────────────────────────────────────" -ForegroundColor Cyan
Write-Host ""
