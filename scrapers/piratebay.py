"""PirateBay scraper via apibay.org JSON API"""
import httpx
from urllib.parse import quote_plus
from .utils import detect_quality
import logging

log = logging.getLogger(__name__)

HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0",
}

TRACKERS = (
    "&tr=udp://tracker.opentrackr.org:1337/announce"
    "&tr=udp://open.demonii.com:1337/announce"
)


async def scrape(query: str, client: httpx.AsyncClient, timeout: int = 15, **kwargs) -> list:
    results = []
    try:
        resp = await client.get(
            "https://apibay.org/q.php",
            params={"q": query, "cat": "0"},
            headers=HEADERS,
            timeout=timeout,
        )
        if resp.status_code != 200:
            return results
        items = resp.json()
        if not isinstance(items, list):
            return results
        items = [i for i in items if i.get("id", "0") != "0"]
        for item in items[:20]:
            name = item.get("name", "")
            info_hash = item.get("info_hash", "")
            size = int(item.get("size", 0))
            seeders = int(item.get("seeders", 0))
            leechers = int(item.get("leechers", 0))
            if not name or not info_hash:
                continue
            magnet = (f"magnet:?xt=urn:btih:{info_hash}"
                      f"&dn={quote_plus(name)}{TRACKERS}")
            size_str = (f"{size/1024/1024:.0f} MiB" if size < 1e9
                        else f"{size/1024/1024/1024:.2f} GiB")
            cat = str(item.get("category", ""))
            category = ("movies" if cat.startswith("2")
                        else "anime" if cat.startswith("5")
                        else "general")
            results.append({
                "source": "piratebay",
                "source_icon": "☠️",
                "name": name,
                "magnet": magnet,
                "torrent_link": "",
                "size": size_str,
                "date": item.get("added", ""),
                "seeders": seeders,
                "leechers": leechers,
                "quality": detect_quality(name),
                "category": category,
                "trusted": item.get("status") in ("vip", "trusted"),
            })
    except Exception as e:
        log.error(f"PirateBay error: {e}")
    return results
