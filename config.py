"""
verticalmedia configuration
Edit this file or use environment variables.
Environment variables take precedence over config values.
"""
import os
from pathlib import Path

try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

# ━━━ qBittorrent ━━━
QBIT_URL = os.getenv("QBIT_URL", "http://localhost:8081")
QBIT_USERNAME = os.getenv("QBIT_USERNAME", "admin")
QBIT_PASSWORD = os.getenv("QBIT_PASSWORD", "adminadmin")

# ━━━ Prowlarr (optional) ━━━
PROWLARR_URL = os.getenv("PROWLARR_URL", "http://localhost:9696")
PROWLARR_KEY = os.getenv("PROWLARR_KEY", "")

# ━━━ TMDB (optional, for movie posters) ━━━
TMDB_KEY = os.getenv("TMDB_KEY", "")
# Get your free key at: https://www.themoviedb.org/settings/api

# ━━━ Media save paths ━━━
SAVE_PATHS = {
    "anime":   os.getenv("PATH_ANIME",   "/downloads/anime"),
    "movies":  os.getenv("PATH_MOVIES",  "/downloads/movies"),
    "shows":   os.getenv("PATH_SHOWS",   "/downloads/shows"),
    "other":   os.getenv("PATH_OTHER",   "/downloads"),
}

# ━━━ Server ━━━
HOST = os.getenv("VM_HOST", "0.0.0.0")
PORT = int(os.getenv("VM_PORT", "7171"))

# ━━━ Search defaults ━━━
DEFAULT_SOURCES = os.getenv(
    "DEFAULT_SOURCES",
    "nyaa,animetosho,yts,piratebay,knaben"
)
DEFAULT_QUALITY = os.getenv("DEFAULT_QUALITY", "1080p")
RESULTS_LIMIT = int(os.getenv("RESULTS_LIMIT", "20"))

# ━━━ Timeouts ━━━
SCRAPER_TIMEOUT = int(os.getenv("SCRAPER_TIMEOUT", "15"))
QBIT_TIMEOUT = int(os.getenv("QBIT_TIMEOUT", "10"))
