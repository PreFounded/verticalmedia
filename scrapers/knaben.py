"""Knaben scraper — general torrent aggregator"""
import httpx
from bs4 import BeautifulSoup
from urllib.parse import quote_plus
from .utils import detect_quality
import logging

log = logging.getLogger(__name__)

HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0",
}


async def scrape(query: str, client: httpx.AsyncClient, timeout: int = 15, **kwargs) -> list:
    results = []
    try:
        url = f"https://knaben.org/search/{quote_plus(query)}/0/0/seeders/1"
        resp = await client.get(url, headers=HEADERS, timeout=timeout, follow_redirects=True)
        if resp.status_code != 200:
            return results
        soup = BeautifulSoup(resp.text, "lxml")
        for row in soup.select("tr.text-nowrap.border-start")[:20]:
            try:
                cells = row.select("td")
                if len(cells) < 5:
                    continue
                name_el = cells[1].select_one("a")
                if not name_el:
                    continue
                name = name_el.get_text(strip=True)
                magnet = name_el.get("href", "")
                if not magnet.startswith("magnet:"):
                    continue
                size = cells[2].get_text(strip=True) if len(cells) > 2 else ""
                try:
                    seeders = int(cells[4].get_text(strip=True))
                except Exception:
                    seeders = 0
                results.append({
                    "source": "knaben",
                    "source_icon": "🔍",
                    "name": name,
                    "magnet": magnet,
                    "size": size,
                    "seeders": seeders,
                    "leechers": 0,
                    "quality": detect_quality(name),
                    "category": "general",
                    "trusted": False,
                })
            except Exception as e:
                log.debug(f"Knaben row error: {e}")
    except Exception as e:
        log.error(f"Knaben error: {e}")
    return results
