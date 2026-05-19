"""AnimeTosho scraper — anime torrents via RSS/API"""
import httpx, re
from bs4 import BeautifulSoup
from .utils import detect_quality
import logging

log = logging.getLogger(__name__)

HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0",
}


async def scrape(query: str, client: httpx.AsyncClient, timeout: int = 15, **kwargs) -> list:
    """Search AnimeTosho via their JSON/RSS API."""
    results = []
    try:
        url = "https://feed.animetosho.org/api"
        params = {"q": query, "t": "search", "limit": 20}
        resp = await client.get(url, params=params, headers=HEADERS, timeout=timeout)
        if resp.status_code != 200:
            return results
        soup = BeautifulSoup(resp.text, "lxml-xml")
        for item in soup.select("item")[:20]:
            try:
                name_el = item.select_one("title")
                if not name_el:
                    continue
                name = name_el.get_text(strip=True)
                magnet_el = (item.select_one('torznab\\:attr[name="magneturl"]') or
                             item.select_one('attr[name="magneturl"]'))
                magnet = magnet_el.get("value", "") if magnet_el else ""
                if not magnet:
                    desc = item.get_text()
                    m = re.search(r'href="(magnet:[^"]+)"', desc)
                    if m:
                        magnet = m.group(1)
                torrent_el = item.select_one('enclosure[type="application/x-bittorrent"]')
                torrent_url = torrent_el.get("url", "") if torrent_el else ""
                size_el = (item.select_one('torznab\\:attr[name="size"]') or
                           item.select_one('attr[name="size"]'))
                size = int(size_el.get("value", 0)) if size_el else 0
                size_str = (f"{size/1024/1024:.0f} MiB" if size < 1e9
                            else f"{size/1024/1024/1024:.2f} GiB") if size > 0 else ""
                seed_el = (item.select_one('torznab\\:attr[name="seeders"]') or
                           item.select_one('attr[name="seeders"]'))
                seeders = int(seed_el.get("value", 0)) if seed_el else 0
                leech_el = (item.select_one('torznab\\:attr[name="leechers"]') or
                            item.select_one('attr[name="leechers"]'))
                leechers = int(leech_el.get("value", 0)) if leech_el else 0
                date_el = item.select_one("pubDate")
                results.append({
                    "source": "animetosho",
                    "source_icon": "🗃️",
                    "name": name,
                    "magnet": magnet,
                    "torrent_link": torrent_url,
                    "size": size_str,
                    "date": date_el.get_text(strip=True) if date_el else "",
                    "seeders": seeders,
                    "leechers": leechers,
                    "quality": detect_quality(name),
                    "category": "anime",
                    "trusted": False,
                })
            except Exception as e:
                log.debug(f"AnimeTosho item: {e}")
    except Exception as e:
        log.error(f"AnimeTosho error: {e}")
    return results
