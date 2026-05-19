# Configuration Reference

## Environment Variables

### Required

| Variable | Default | Description |
|----------|---------|-------------|
| `QBIT_URL` | `http://localhost:8081` | qBittorrent Web UI URL |
| `QBIT_USERNAME` | `admin` | qBittorrent username |
| `QBIT_PASSWORD` | `adminadmin` | qBittorrent password |

### Optional — Prowlarr

| Variable | Default | Description |
|----------|---------|-------------|
| `PROWLARR_URL` | `http://localhost:9696` | Prowlarr URL |
| `PROWLARR_KEY` | _(empty)_ | Prowlarr API key |

### Optional — Download Paths

| Variable | Default | Description |
|----------|---------|-------------|
| `PATH_ANIME` | `/downloads/anime` | Where anime torrents save |
| `PATH_MOVIES` | `/downloads/movies` | Where movie torrents save |
| `PATH_SHOWS` | `/downloads/shows` | Where TV show torrents save |

### Optional — Server

| Variable | Default | Description |
|----------|---------|-------------|
| `VM_HOST` | `0.0.0.0` | Bind address |
| `VM_PORT` | `7171` | Port to listen on |
| `SCRAPER_TIMEOUT` | `15` | Seconds before scraper times out |

---

## qBittorrent Setup

1. Open qBittorrent → Preferences → Web UI
2. Check **Enable Web UI** and set port (default 8081)
3. Set username and password
4. Check **Bypass authentication for clients on localhost** (if on same machine)

### Categories (so files go to the right folders)

In qBittorrent → Preferences → Downloads → Manage Categories:
- Add: `anime` → `/your/anime/path`  
- Add: `movies` → `/your/movies/path`
- Add: `shows` → `/your/shows/path`

These must match `PATH_ANIME`, `PATH_MOVIES`, `PATH_SHOWS` in your config.

---

## Reverse Proxy (Nginx)

```nginx
server {
    listen 80;
    server_name media.yourserver.local;

    location / {
        proxy_pass http://localhost:7171;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

---

## Firewall

```bash
# Allow access from local network
sudo ufw allow from 192.168.1.0/24 to any port 7171

# Allow access from Tailscale
sudo ufw allow from 100.0.0.0/8 to any port 7171
```
