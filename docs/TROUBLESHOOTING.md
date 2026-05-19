# Troubleshooting Guide

## Installation Issues

### "Python not found" on Linux
```bash
# Ubuntu/Debian
sudo apt update && sudo apt install python3 python3-pip

# Arch Linux
sudo pacman -S python python-pip

# Fedora
sudo dnf install python3 python3-pip
```

### "pip install fails with externally-managed-environment"
```bash
pip install -r requirements.txt --break-system-packages
# OR use a virtual environment:
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt
```

### Service won't start after install
```bash
systemctl --user status verticalmedia
journalctl --user -u verticalmedia -n 50
systemctl --user restart verticalmedia
```

---

## Connection Issues

### "qBittorrent: disconnected" in status
1. Make sure qBittorrent is running
2. Check Web UI is enabled: Preferences → Web UI → Enable Web UI
3. Verify the URL in Settings matches exactly (check port)
4. Enable bypass: qBittorrent → Web UI → Bypass authentication for localhost

### Prowlarr shows 0 results
1. Verify Prowlarr is running: `curl http://localhost:9696`
2. Check API key: Prowlarr → Settings → General → API Key
3. Verify Prowlarr has indexers configured: Prowlarr → Indexers
4. Test: `curl "http://localhost:9696/api/v1/search?query=test&apikey=YOUR_KEY"`

---

## Search Issues

### No results from Nyaa
- Check if Nyaa is accessible: `curl -I https://nyaa.si`
- Try other sources via Settings
- Use Prowlarr which can route through proxies

### Results are slow
- Normal during first search (connections warm up)
- Increase timeout: `SCRAPER_TIMEOUT=30` in `.env`
- Disable slow sources via Settings

---

## Download Issues

### Torrents not saving to correct folder
1. Check qBittorrent categories: Settings → Downloads → Categories
2. Verify category paths match config:
   - `anime` → `/your/anime/path` (must match `PATH_ANIME`)
3. Ensure qBittorrent user has write permission to those folders

### "403 Forbidden" when adding torrent
qBittorrent requires auth. Set correct credentials or enable:
"Bypass authentication for clients on localhost" in qBittorrent Web UI settings.

---

## Docker Issues

### Can't connect to qBittorrent from container
```yaml
# Linux host (docker bridge gateway)
- QBIT_URL=http://172.17.0.1:8081
# Or use host networking:
network_mode: host
```

---

## Performance

### Server is slow / high CPU
- Scrapers run concurrently — normal during search
- Disable unused sources in Settings to reduce load
