"""SolidTorrents scraper — privacy-focused torrent search"""
import httpx
from urllib.parse import quote_plus
from .utils import detect_quality, format_size
import logging

log = logging.getLogger(__name__)

HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0",
}


async def scrape(query: str, client: httpx.AsyncClient, timeout: int = 15, **kwargs) -> list:
    results = []
    try:
        resp = await client.get(
            "https://solidtorrents.to/api/v1/search",
            params={"q": query, "sort": "seeders"},
            headers=HEADERS,
            timeout=timeout,
        )
        if resp.status_code != 200:
            return results
        for item in resp.json().get("results", [])[:20]:
            name = item.get("title", "")
            if not name:
                continue
            swarm = item.get("swarm", {})
            total_size = sum(f.get("size", 0) for f in item.get("files", []))
            info_hash = item.get("infohash", "")
            magnet = (f"magnet:?xt=urn:btih:{info_hash}"
                      f"&dn={quote_plus(name)}"
                      f"&tr=udp://tracker.opentrackr.org:1337/announce"
                      if info_hash else "")
            results.append({
                "source": "solidtorrents",
                "source_icon": "💎",
                "name": name,
                "magnet": magnet,
                "torrent_link": "",
                "size": format_size(total_size) if total_size > 0 else "",
                "date": item.get("imported", ""),
                "seeders": swarm.get("seeders", 0),
                "leechers": swarm.get("leechers", 0),
                "quality": detect_quality(name),
                "category": "general",
                "trusted": False,
            })
    except Exception as e:
        log.error(f"SolidTorrents error: {e}")
    return results
