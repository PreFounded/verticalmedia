"""Nyaa.si scraper — anime torrents"""
import httpx
from bs4 import BeautifulSoup
from urllib.parse import quote_plus
from .utils import detect_quality, detect_batch, parse_size
import logging

log = logging.getLogger(__name__)

HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0",
    "Accept-Language": "en-US,en;q=0.9",
}


async def scrape(query: str, client: httpx.AsyncClient,
                 timeout: int = 15, batch: bool = False) -> list:
    """Search nyaa.si for anime torrents."""
    results = []
    try:
        if batch:
            url = (f"https://nyaa.si/?f=0&c=1_0"
                   f"&q={quote_plus(query + ' batch')}"
                   f"&s=size&o=desc")
        else:
            url = (f"https://nyaa.si/?f=0&c=0_0"
                   f"&q={quote_plus(query)}"
                   f"&s=seeders&o=desc")
        resp = await client.get(url, headers=HEADERS, timeout=timeout)
        if resp.status_code != 200:
            return results
        soup = BeautifulSoup(resp.text, "lxml")
        for row in soup.select("table.torrent-list tbody tr")[:20]:
            try:
                cells = row.select("td")
                if len(cells) < 8:
                    continue
                name_cell = cells[1].select_one("a:not(.comments)")
                if not name_cell:
                    continue
                name = name_cell.get_text(strip=True)
                links = cells[2].select("a")
                magnet = next((l.get("href", "") for l in links
                               if l.get("href", "").startswith("magnet:")), "")
                torrent = next((
                    f"https://nyaa.si{l.get('href', '')}"
                    for l in links
                    if l.get("href", "").endswith(".torrent")), "")
                size_str = cells[3].get_text(strip=True)
                seeders = int(cells[5].get_text(strip=True) or 0)
                leechers = int(cells[6].get_text(strip=True) or 0)
                is_batch = batch or detect_batch(name)
                if batch and parse_size(size_str) < 500 * 1024 * 1024:
                    continue
                results.append({
                    "source": "nyaa",
                    "source_icon": "🌸",
                    "name": name,
                    "magnet": magnet,
                    "torrent_link": torrent,
                    "size": size_str,
                    "date": cells[4].get_text(strip=True),
                    "seeders": seeders,
                    "leechers": leechers,
                    "quality": detect_quality(name),
                    "category": "anime",
                    "trusted": "success" in " ".join(row.get("class", [])),
                    "is_batch": is_batch,
                })
            except Exception as e:
                log.debug(f"Nyaa row error: {e}")
    except Exception as e:
        log.error(f"Nyaa error: {e}")
    return results


async def scrape_batch(query: str, client: httpx.AsyncClient,
                       timeout: int = 15) -> list:
    """Search Nyaa specifically for season/batch packs."""
    results = []
    try:
        searches = [f"{query} batch", f"{query} complete", f"{query} season"]
        for search in searches:
            url = (f"https://nyaa.si/?f=0&c=1_0"
                   f"&q={quote_plus(search)}"
                   f"&s=size&o=desc")
            resp = await client.get(url, headers=HEADERS, timeout=timeout)
            if resp.status_code != 200:
                continue
            soup = BeautifulSoup(resp.text, "lxml")
            for row in soup.select("table.torrent-list tbody tr")[:15]:
                try:
                    cells = row.select("td")
                    if len(cells) < 8:
                        continue
                    name_cell = row.select_one("td:nth-child(2) a:not(.comments)")
                    name = name_cell.get_text(strip=True) if name_cell else ""
                    if not name or not detect_batch(name):
                        continue
                    links = cells[2].select("a")
                    magnet = next((l.get("href", "") for l in links
                                   if l.get("href", "").startswith("magnet:")), "")
                    size_str = cells[3].get_text(strip=True)
                    if parse_size(size_str) < 500 * 1024 * 1024:
                        continue
                    seeders = int(cells[5].get_text(strip=True) or 0)
                    if magnet and seeders > 0:
                        results.append({
                            "source": "nyaa_batch",
                            "source_icon": "🌸📦",
                            "name": name,
                            "magnet": magnet,
                            "size": size_str,
                            "date": cells[4].get_text(strip=True),
                            "seeders": seeders,
                            "leechers": int(cells[6].get_text(strip=True) or 0),
                            "quality": detect_quality(name),
                            "category": "anime",
                            "trusted": "success" in " ".join(row.get("class", [])),
                            "is_batch": True,
                        })
                except Exception:
                    continue
            if results:
                break
    except Exception as e:
        log.error(f"Nyaa batch error: {e}")
    seen = set()
    unique = []
    for r in results:
        key = r["name"][:40].lower()
        if key not in seen:
            seen.add(key)
            unique.append(r)
    return unique
