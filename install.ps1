#Requires -Version 5.1
<#
.SYNOPSIS
    verticalmedia Windows installer
.DESCRIPTION
    Fully self-contained installer. Installs Python, Git and qBittorrent
    automatically if missing. Configures everything unattended.
.EXAMPLE
    irm https://raw.githubusercontent.com/PreFounded/verticalmedia/main/install.ps1 | iex
#>

# ─────────────────────────────────────────────────────────────────────────────
#  Admin self-elevation — must be first
# ─────────────────────────────────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "  Requesting administrator privileges..." -ForegroundColor Yellow
    $relaunch = if ($PSCommandPath) {
        "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    } else {
        # Running via irm | iex — re-download in the elevated session
        $url = "https://raw.githubusercontent.com/PreFounded/verticalmedia/main/install.ps1"
        "-NoProfile -ExecutionPolicy Bypass -Command `"[Net.ServicePointManager]::SecurityProtocol='Tls12'; irm '$url' | iex`""
    }
    Start-Process powershell $relaunch -Verb RunAs -Wait
    exit
}

$ErrorActionPreference = "Continue"

# Global safety net: any unhandled terminating error (missing exe, failed cast,
# .NET exception, etc.) lands here instead of silently closing the window.
trap {
    Write-Host ""
    Write-Host "  x  Unexpected error: $_" -ForegroundColor Red
    Write-Host "     Line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  If you need help, open an issue at:" -ForegroundColor DarkGray
    Write-Host "  https://github.com/PreFounded/verticalmedia/issues" -ForegroundColor DarkGray
    Write-Host ""
    Read-Host "  Press Enter to close"
    break
}

$REPO       = "https://github.com/PreFounded/verticalmedia.git"
$PY_VERSION = "3.12.7"
$PY_URL     = "https://www.python.org/ftp/python/$PY_VERSION/python-$PY_VERSION-amd64.exe"

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
    Write-Host "  (running as Administrator)" -ForegroundColor DarkGray
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
    Read-Host "  Press Enter to exit"
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
    [Net.ServicePointManager]::SecurityProtocol = "Tls12"
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
}

# ─────────────────────────────────────────────────────────────────────────────
#  Python installer
# ─────────────────────────────────────────────────────────────────────────────

function Install-Python {
    Show-Section "Installing Python $PY_VERSION"
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Info "Using winget (1-3 min)..."
        winget install --id Python.Python.3.12 --source winget `
            --accept-package-agreements --accept-source-agreements -e --silent
        Refresh-Path
    } else {
        $installer = Join-Path $env:TEMP "python-installer.exe"
        Download-File $PY_URL $installer
        Write-Info "Running Python installer silently (1-2 min)..."
        Start-Process $installer "/quiet InstallAllUsers=1 PrependPath=1 Include_launcher=0 Include_test=0" -Wait
        Remove-Item $installer -Force
        Refresh-Path
    }
    $v = python --version 2>&1
    if ($LASTEXITCODE -ne 0) { Stop-Install "Python installation failed. Install manually from https://python.org/downloads" }
    Write-Ok "Python installed: $v"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Git installer
# ─────────────────────────────────────────────────────────────────────────────

function Install-Git {
    Show-Section "Installing Git"
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Info "Using winget (1-2 min)..."
        winget install --id Git.Git --source winget `
            --accept-package-agreements --accept-source-agreements -e --silent
        Refresh-Path
    } else {
        Write-Info "Fetching latest Git release..."
        $release = Invoke-RestMethod "https://api.github.com/repos/git-for-windows/git/releases/latest"
        $asset   = $release.assets | Where-Object { $_.name -match "64-bit\.exe$" } | Select-Object -First 1
        if (-not $asset) { Stop-Install "Could not find Git installer. Get it from https://git-scm.com/download/win" }
        $installer = Join-Path $env:TEMP "git-installer.exe"
        Download-File $asset.browser_download_url $installer
        Write-Info "Running Git installer silently (~1 min)..."
        Start-Process $installer "/VERYSILENT /NORESTART /NOCANCEL /SP-" -Wait
        Remove-Item $installer -Force
        Refresh-Path
    }
    $v = git --version 2>&1
    if ($LASTEXITCODE -ne 0) { Stop-Install "Git installation failed. Install manually from https://git-scm.com/download/win" }
    Write-Ok "Git installed: $v"
}

# ─────────────────────────────────────────────────────────────────────────────
#  qBittorrent — find, install, configure
# ─────────────────────────────────────────────────────────────────────────────

function Find-QBitExe {
    $candidates = @(
        "$env:ProgramFiles\qBittorrent\qbittorrent.exe",
        "${env:ProgramFiles(x86)}\qBittorrent\qbittorrent.exe"
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }

    # Registry lookup
    foreach ($hive in @("HKLM:\SOFTWARE", "HKLM:\SOFTWARE\WOW6432Node")) {
        $loc = (Get-ItemProperty "$hive\Microsoft\Windows\CurrentVersion\Uninstall\qBittorrent" -ErrorAction SilentlyContinue).InstallLocation
        if ($loc) {
            $exe = Join-Path $loc "qbittorrent.exe"
            if (Test-Path $exe) { return $exe }
        }
    }

    $cmd = Get-Command qbittorrent -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Install-QBittorrent {
    Show-Section "Installing qBittorrent"
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Info "Using winget (1-2 min)..."
        winget install --id qBittorrent.qBittorrent --source winget `
            --accept-package-agreements --accept-source-agreements -e --silent
        Refresh-Path
    } else {
        Write-Info "Fetching latest qBittorrent release..."
        $release = Invoke-RestMethod "https://api.github.com/repos/qbittorrent/qBittorrent/releases/latest"
        $asset   = $release.assets | Where-Object { $_.name -match "x64_setup\.exe$" -or $_.name -match "x86_64.*\.exe$" } | Select-Object -First 1
        if (-not $asset) {
            # Fallback pattern for different naming conventions
            $asset = $release.assets | Where-Object { $_.name -match "setup\.exe$" } | Select-Object -First 1
        }
        if (-not $asset) { Stop-Install "Could not find qBittorrent installer. Download from https://qbittorrent.org" }
        $installer = Join-Path $env:TEMP "qbittorrent-setup.exe"
        Download-File $asset.browser_download_url $installer
        Write-Info "Running qBittorrent installer silently (~1 min)..."
        Start-Process $installer "/S" -Wait   # NSIS silent flag
        Remove-Item $installer -Force
        Refresh-Path
    }
    $exe = Find-QBitExe
    if (-not $exe) { Stop-Install "qBittorrent installation failed or exe not found." }
    Write-Ok "qBittorrent installed: $exe"
    return $exe
}

function Update-IniSection([string]$iniPath, [string]$section, [hashtable]$keys) {
    # Parse the existing ini into an ordered structure
    $ini     = [ordered]@{}
    $secList = [System.Collections.Generic.List[string]]::new()
    $curSec  = $null

    if (Test-Path $iniPath) {
        foreach ($line in [System.IO.File]::ReadAllLines($iniPath, [Text.Encoding]::UTF8)) {
            $line = $line.TrimEnd()
            if ($line -match '^\[(.+)\]$') {
                $curSec = $Matches[1]
                if (-not $ini.Contains($curSec)) {
                    $ini[$curSec] = [ordered]@{}
                    $secList.Add($curSec)
                }
            } elseif ($line -match '^([^=]+)=(.*)$' -and $curSec) {
                $ini[$curSec][$Matches[1]] = $Matches[2]
            }
        }
    }

    # Apply updates
    if (-not $ini.Contains($section)) {
        $ini[$section] = [ordered]@{}
        $secList.Add($section)
    }
    foreach ($kv in $keys.GetEnumerator()) { $ini[$section][$kv.Key] = $kv.Value }

    # Write back
    New-Item -ItemType Directory -Path (Split-Path $iniPath -Parent) -Force | Out-Null
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($sec in $secList) {
        $out.Add("[$sec]")
        foreach ($kv in $ini[$sec].GetEnumerator()) { $out.Add("$($kv.Key)=$($kv.Value)") }
        $out.Add("")
    }
    [System.IO.File]::WriteAllLines($iniPath, $out, [Text.Encoding]::UTF8)
}

function Install-NSSM {
    Show-Section "Installing NSSM (Windows service manager)"
    Write-Info "NSSM runs verticalmedia as a proper Windows service that starts with the OS."
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Info "Using winget..."
        winget install --id NSSM.NSSM --source winget `
            --accept-package-agreements --accept-source-agreements -e --silent
        Refresh-Path
    } else {
        Write-Info "Downloading NSSM 2.24 from nssm.cc..."
        $zipPath = Join-Path $env:TEMP "nssm.zip"
        try {
            Download-File "https://nssm.cc/release/nssm-2.24.zip" $zipPath
            $extractDir = Join-Path $env:TEMP "nssm-extract"
            Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
            # Prefer 64-bit binary
            $nssmExe = Get-ChildItem "$extractDir" -Filter "nssm.exe" -Recurse |
                       Where-Object { $_.FullName -match "win64" } |
                       Select-Object -First 1
            if (-not $nssmExe) {
                $nssmExe = Get-ChildItem "$extractDir" -Filter "nssm.exe" -Recurse |
                           Select-Object -First 1
            }
            if ($nssmExe) {
                Copy-Item $nssmExe.FullName "C:\Windows\System32\nssm.exe" -Force
                Write-Ok "NSSM installed to System32"
            } else {
                Write-Warn "Could not locate nssm.exe in archive — falling back to Task Scheduler."
            }
        } catch {
            Write-Warn "NSSM download failed: $_ — falling back to Task Scheduler."
        } finally {
            Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
            Remove-Item (Join-Path $env:TEMP "nssm-extract") -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Refresh-Path
    $check = Get-Command nssm -ErrorAction SilentlyContinue
    if ($check) { Write-Ok "NSSM ready: $(nssm version 2>&1 | Select-Object -First 1)" }
}

function Configure-QBittorrent([string]$qbitExe, [string]$port, [string]$username,
                               [hashtable]$categories) {
    $iniPath = Join-Path $env:APPDATA "qBittorrent\qBittorrent.ini"

    # Stop qBittorrent if running so we can safely write the ini
    $proc = Get-Process qbittorrent -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Info "Stopping qBittorrent to apply configuration..."
        $proc | Stop-Process -Force
        Start-Sleep -Seconds 2
    }

    Write-Info "Writing qBittorrent configuration..."

    # Accept EULA / legal notice (skips first-run dialog)
    Update-IniSection $iniPath "LegalNotice" @{ "Accepted" = "true" }

    # Web UI settings — LocalHostAuth=false means no password needed from localhost
    Update-IniSection $iniPath "Preferences" @{
        "WebUI\Enabled"             = "true"
        "WebUI\Port"                = $port
        "WebUI\LocalHostAuth"       = "false"
        "WebUI\Username"            = $username
        "General\StartMinimized"    = "true"
        "General\CloseToTray"       = "true"
        "Queueing\MaxActiveDownloads" = "5"
        "Queueing\MaxActiveTorrents"  = "10"
    }

    # Start qBittorrent minimised to tray
    Write-Info "Starting qBittorrent..."
    Start-Process $qbitExe -WindowStyle Hidden
    Start-Sleep -Seconds 3   # give it a moment to start the Web UI

    # Wait for the Web UI to be ready (up to 20 seconds)
    $baseUrl = "http://localhost:$port"
    $ready   = $false
    Write-Host "     Waiting for Web UI " -NoNewline -ForegroundColor DarkGray
    for ($i = 0; $i -lt 20; $i++) {
        try {
            $r = Invoke-WebRequest "$baseUrl/api/v2/app/version" -UseBasicParsing -TimeoutSec 1 -ErrorAction Stop
            if ($r.StatusCode -eq 200) { $ready = $true; break }
        } catch { }
        Write-Host "." -NoNewline -ForegroundColor DarkGray
        Start-Sleep -Seconds 1
    }
    Write-Host ""

    if (-not $ready) {
        Write-Warn "qBittorrent Web UI did not respond in time — categories will need to be set manually."
        return
    }
    Write-Ok "qBittorrent Web UI is up at $baseUrl"

    # Create download categories via the API
    foreach ($kv in $categories.GetEnumerator()) {
        $name     = $kv.Key
        $savePath = $kv.Value
        try {
            $body = "category=$name&savePath=$([Uri]::EscapeDataString($savePath))"
            Invoke-WebRequest "$baseUrl/api/v2/torrents/createCategory" -Method POST `
                -Body $body -ContentType "application/x-www-form-urlencoded" `
                -UseBasicParsing -ErrorAction Stop | Out-Null
            Write-Ok "Category '$name' → $savePath"
        } catch {
            Write-Warn "Could not create category '$name' — add it manually in qBittorrent."
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  Step 1 — Requirements: Python + Git
# ─────────────────────────────────────────────────────────────────────────────

Show-Header
Show-Section "Requirements"

# Python
$pythonOk = $false
try {
    $pyraw = python --version 2>&1
    if ($pyraw -match "Python (\d+)\.(\d+)") {
        $maj = [int]$Matches[1]; $min = [int]$Matches[2]
        if ($maj -gt 3 -or ($maj -eq 3 -and $min -ge 10)) { Write-Ok $pyraw; $pythonOk = $true }
        else { Write-Warn "Found $pyraw — 3.10+ required, will upgrade." }
    }
} catch { Write-Warn "Python not found — will install automatically." }
if (-not $pythonOk) { Install-Python }

# Git
$gitOk = $false
try { $gitraw = git --version 2>&1; Write-Ok $gitraw; $gitOk = $true }
catch { Write-Warn "Git not found — will install automatically." }
if (-not $gitOk) { Install-Git }

# ─────────────────────────────────────────────────────────────────────────────
#  Step 2 — qBittorrent
# ─────────────────────────────────────────────────────────────────────────────

Show-Section "qBittorrent"
Write-Info "qBittorrent handles all torrent downloads. verticalmedia talks to it via its Web UI."
Write-Host ""

$qbitExe      = Find-QBitExe
$qbitInstalled = $null -ne $qbitExe

if ($qbitInstalled) {
    Write-Ok "qBittorrent found: $qbitExe"
} else {
    Write-Warn "qBittorrent not found — will install automatically."
    $qbitExe = Install-QBittorrent
}

$qbitPort = Read-Input "qBittorrent Web UI port" "8081"
$qbitUser = Read-Input "qBittorrent username"    "admin"

Show-Section "Download paths"
Write-Info "Choose a media folder — Anime, Movies and Shows subfolders are created inside it."
Write-Host ""
$defaultMedia = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "VerticalMedia"
$mediaDir     = Read-Input "Media folder" $defaultMedia

$pathAnime  = Join-Path $mediaDir "Anime"
$pathMovies = Join-Path $mediaDir "Movies"
$pathShows  = Join-Path $mediaDir "Shows"

foreach ($p in @($pathAnime, $pathMovies, $pathShows)) {
    New-Item -ItemType Directory -Path $p -Force | Out-Null
}
Write-Ok "$mediaDir\{Anime, Movies, Shows}"

# Configure Web UI + categories unattended
Configure-QBittorrent $qbitExe $qbitPort $qbitUser @{
    "anime"  = $pathAnime
    "movies" = $pathMovies
    "shows"  = $pathShows
}

# Add qBittorrent to Windows startup (runs at login, hidden to tray)
$qbitStartup = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
Set-ItemProperty $qbitStartup -Name "qBittorrent" -Value "`"$qbitExe`" --no-splash" -ErrorAction SilentlyContinue
Write-Ok "qBittorrent added to Windows startup"

# ─────────────────────────────────────────────────────────────────────────────
#  Step 3 — verticalmedia install location
# ─────────────────────────────────────────────────────────────────────────────

Show-Section "Install location"

Write-Info "This is where the verticalmedia app files will be placed."
Write-Info "The folder will be created automatically if it doesn't exist."
Write-Info "Avoid paths with spaces (e.g. prefer C:\Apps\verticalmedia)."
Write-Host ""

$defaultDir = Join-Path $env:USERPROFILE "verticalmedia"
$installDir = Read-Input "Install path" $defaultDir

if ([string]::IsNullOrWhiteSpace($installDir)) {
    Write-Warn "No path entered — using default: $defaultDir"
    $installDir = $defaultDir
}

if (Test-Path (Join-Path $installDir ".git")) {
    Write-Warn "Existing installation found — will update to latest."
} elseif (Test-Path $installDir) {
    Write-Warn "Folder already exists — app files will be placed inside it."
} else {
    try {
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    } catch {
        Stop-Install "Cannot create directory: $installDir`nCheck that you have write permission to the parent folder."
    }
}
Write-Ok "Install path: $installDir"

# ─────────────────────────────────────────────────────────────────────────────
#  Step 4 — Clone / update
# ─────────────────────────────────────────────────────────────────────────────

Show-Section "Downloading verticalmedia"

if (Test-Path (Join-Path $installDir ".git")) {
    Write-Info "Pulling latest changes..."
    git -C $installDir pull --ff-only
    if ($LASTEXITCODE -ne 0) { Stop-Install "git pull failed. Check your network and try again." }
} else {
    Write-Info "Cloning repository (~20s, depends on connection)..."
    git clone $REPO $installDir
    if ($LASTEXITCODE -ne 0) { Stop-Install "git clone failed. Check your network and try again." }
}
Write-Ok "Files ready"

# ─────────────────────────────────────────────────────────────────────────────
#  Step 5 — Python virtual environment + dependencies
# ─────────────────────────────────────────────────────────────────────────────

Show-Section "Python environment"

$venv   = Join-Path $installDir ".venv"
$pyExe  = Join-Path $venv "Scripts\python.exe"
$pipExe = Join-Path $venv "Scripts\pip.exe"

if (-not (Test-Path $venv)) {
    Write-Info "Creating virtual environment..."
    python -m venv $venv
    if ($LASTEXITCODE -ne 0) { Stop-Install "Failed to create virtual environment." }
}

# pip.exe is sometimes missing from new venvs on fresh Python installs — bootstrap it
if (-not (Test-Path $pipExe)) {
    Write-Info "pip not found in venv — bootstrapping..."
    & $pyExe -m ensurepip --upgrade
    if (-not (Test-Path $pipExe)) {
        Stop-Install "pip is missing from the virtual environment.`nRun manually: python -m ensurepip`nThen re-run this installer."
    }
}

Write-Info "Upgrading pip..."
& $pipExe install -q --upgrade pip
Write-Info "Installing packages (~30-90 sec)..."
& $pipExe install -r (Join-Path $installDir "requirements.txt")
if ($LASTEXITCODE -ne 0) { Stop-Install "pip install failed. See error above." }
Write-Ok "Dependencies installed"

# ─────────────────────────────────────────────────────────────────────────────
#  Step 6 — Configuration (.env)
# ─────────────────────────────────────────────────────────────────────────────

$envFile  = Join-Path $installDir ".env"
$doConfig = $true

if (Test-Path $envFile) {
    Show-Section "Existing configuration found"
    $doConfig = Read-YN "Reconfigure settings?" $false
}

if ($doConfig) {
    Show-Section "Prowlarr (optional)"
    Write-Info "Prowlarr aggregates many torrent indexers into one API."
    Write-Info "Skip this if you don't use it — configurable later via Settings."
    Write-Host ""
    $prowlarrUrl = ""; $prowlarrKey = ""
    if (Read-YN "Do you use Prowlarr?" $false) {
        $prowlarrUrl = Read-Input "Prowlarr URL"     "http://localhost:9696"
        $prowlarrKey = Read-Input "Prowlarr API key" ""
    }

    Show-Section "Server settings"
    $vmPort = Read-Input "Port for verticalmedia to listen on" "7171"

    # qBit URL auto-filled from what we configured above
    $qbitUrl = "http://localhost:$qbitPort"

    @"
# qBittorrent — localhost auth is disabled, any credentials work
QBIT_URL=$qbitUrl
QBIT_USERNAME=$qbitUser
QBIT_PASSWORD=

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
                Where-Object { $_ -match "^VM_PORT=" } | Select-Object -First 1
    if ($portLine) { $vmPort = $portLine -replace "^VM_PORT=\s*", "" }
}

# ─────────────────────────────────────────────────────────────────────────────
#  Step 6.5 — Windows Firewall rules
# ─────────────────────────────────────────────────────────────────────────────
Show-Section "Firewall"
try {
    # Remove stale rules from previous installs
    Remove-NetFirewallRule -DisplayName "verticalmedia*"     -ErrorAction SilentlyContinue
    Remove-NetFirewallRule -DisplayName "qBittorrent WebUI*" -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "verticalmedia ($vmPort)" `
        -Direction Inbound -Protocol TCP -LocalPort ([int]$vmPort) `
        -Action Allow -Profile Any | Out-Null
    New-NetFirewallRule -DisplayName "qBittorrent WebUI ($qbitPort)" `
        -Direction Inbound -Protocol TCP -LocalPort ([int]$qbitPort) `
        -Action Allow -Profile Any | Out-Null
    Write-Ok "Firewall rules added (port $vmPort for verticalmedia, port $qbitPort for qBittorrent)"
} catch {
    Write-Warn "Could not add firewall rules automatically: $_"
    Write-Info "Add manually: New-NetFirewallRule -Direction Inbound -Protocol TCP -LocalPort $vmPort -Action Allow"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Step 7 — Always write run.bat
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
#  Step 8 — Run on startup (optional)
# ─────────────────────────────────────────────────────────────────────────────

Show-Section "Run verticalmedia on startup (optional)"
Write-Info "Without a service, double-click run.bat to start verticalmedia."
Write-Host ""

# Auto-install NSSM if not present — it gives proper NT service semantics
# (starts at boot as a service, not just at user login)
$nssm = Get-Command nssm -ErrorAction SilentlyContinue
if (-not $nssm) {
    Install-NSSM
    $nssm = Get-Command nssm -ErrorAction SilentlyContinue
}

$schtasks = Get-Command schtasks -ErrorAction SilentlyContinue

if ($nssm) {
    if (Read-YN "Install as a Windows service via NSSM? (auto-starts with Windows)" $true) {
        $svcName = "verticalmedia"
        $status  = nssm status $svcName 2>&1
        if ($LASTEXITCODE -eq 0 -and "$status" -notmatch "No such service") {
            Write-Info "Removing previous service..."
            nssm stop   $svcName 2>&1 | Out-Null
            nssm remove $svcName confirm 2>&1 | Out-Null
        }
        # Wrap paths in quotes so Windows SCM handles spaces in the install path correctly
        nssm install $svcName "`"$pyExe`"" "-m" "uvicorn" "main:app" "--host" "0.0.0.0" "--port" $vmPort
        nssm set $svcName AppDirectory  "`"$installDir`""
        nssm set $svcName Start         SERVICE_AUTO_START
        # config.py calls load_dotenv() which reads .env from AppDirectory automatically
        nssm start $svcName
        Write-Ok "Service installed and started (auto-starts with Windows)"
        Write-Info "Manage: nssm start|stop|restart verticalmedia"
    } else {
        Write-Ok "Skipped — use run.bat to start manually."
    }
} elseif ($schtasks) {
    if (Read-YN "Register as a login startup task via Task Scheduler?" $true) {
        # Task runs as the current user at logon; config.py load_dotenv() reads .env
        # from WorkingDirectory so no environment variables need to be baked in here.
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Principals>
    <Principal id="Author">
      <UserId>$currentUser</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Triggers><LogonTrigger><Enabled>true</Enabled></LogonTrigger></Triggers>
  <Settings>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <Hidden>true</Hidden>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
  </Settings>
  <Actions>
    <Exec>
      <Command>$pyExe</Command>
      <Arguments>-m uvicorn main:app --host 0.0.0.0 --port $vmPort</Arguments>
      <WorkingDirectory>$installDir</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@
        $xmlPath = Join-Path $env:TEMP "verticalmedia-task.xml"
        [System.IO.File]::WriteAllText($xmlPath, $taskXml, [Text.Encoding]::Unicode)
        schtasks /Create /TN "verticalmedia" /XML $xmlPath /F | Out-Null
        Remove-Item $xmlPath -Force
        Write-Ok "Startup task registered — launches at login"
        Write-Info "Manage: Task Scheduler > verticalmedia"
    } else {
        Write-Ok "Skipped — use run.bat to start manually."
    }
} else {
    Write-Warn "NSSM not found — skipping service setup."
    Write-Info "For auto-start: install NSSM from https://nssm.cc and re-run."
    Write-Ok "run.bat written — double-click to start"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Done
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  ──────────────────────────────────────────────" -ForegroundColor Cyan
Write-Host "   All done!" -ForegroundColor Green
Write-Host ""
Write-Host "   verticalmedia > " -NoNewline -ForegroundColor DarkGray
Write-Host "http://localhost:$vmPort" -ForegroundColor Cyan
Write-Host "   qBittorrent   > " -NoNewline -ForegroundColor DarkGray
Write-Host "http://localhost:$qbitPort" -ForegroundColor DarkGray
Write-Host ""
Write-Host "   Config : $envFile" -ForegroundColor DarkGray
Write-Host "   Run    : $runBat" -ForegroundColor DarkGray
Write-Host "  ──────────────────────────────────────────────" -ForegroundColor Cyan
Write-Host ""
Read-Host "  Press Enter to close"
