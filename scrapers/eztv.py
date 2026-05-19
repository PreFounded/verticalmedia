"""EZTV scraper — TV show torrents with season pack support"""
import httpx
from .utils import detect_quality, detect_batch, format_size
import logging

log = logging.getLogger(__name__)

HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0",
}


async def scrape(query: str, client: httpx.AsyncClient, timeout: int = 15, **kwargs) -> list:
    results = []
    try:
        resp = await client.get(
            "https://eztvx.to/api/get-torrents",
            params={"keywords": query, "limit": 30, "page": 1},
            headers=HEADERS,
            timeout=timeout,
            follow_redirects=True,
        )
        if resp.status_code != 200:
            return results
        for t in resp.json().get("torrents", []):
            name = t.get("filename", t.get("title", ""))
            if not name:
                continue
            size = t.get("size_bytes", 0)
            results.append({
                "source": "eztv",
                "source_icon": "📺",
                "name": name,
                "magnet": t.get("magnet_url", ""),
                "torrent_link": t.get("torrent_url", ""),
                "size": format_size(size) if isinstance(size, int) and size > 0 else "",
                "date": t.get("date_released_unix", ""),
                "seeders": t.get("seeds", 0),
                "leechers": 0,
                "quality": detect_quality(name),
                "category": "shows",
                "trusted": False,
                "is_batch": detect_batch(name, size if isinstance(size, int) else 0),
            })
    except Exception as e:
        log.error(f"EZTV error: {e}")
    return results
