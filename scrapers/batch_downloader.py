#!/usr/bin/env python3
"""
Batch Episode Downloader — Inspired by Tokyo Downloader
Adapted for verticallab: Nyaa + TokyoInsider → qBittorrent
"""
import httpx, asyncio, re, logging
from bs4 import BeautifulSoup
from urllib.parse import quote_plus

log = logging.getLogger(__name__)

try:
    from config import QBIT_URL, SAVE_PATHS, QBIT_TIMEOUT
except ImportError:
    QBIT_URL = "http://localhost:8081"
    QBIT_TIMEOUT = 10
    SAVE_PATHS = {
        "anime": "/downloads/anime",
        "movies": "/downloads/movies",
        "shows": "/downloads/shows",
        "general": "/downloads",
    }

HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0",
    "Accept-Language": "en-US,en;q=0.9",
}

from .utils import detect_batch as _detect_batch


async def get_tokyo_insider_episodes(
        anime_name: str,
        ep_start: int,
        ep_end: int,
        client: httpx.AsyncClient) -> list:
    """Scrape TokyoInsider for episode download links."""
    results = []
    try:
        search_url = "https://www.tokyoinsider.com/anime/search"
        params = {"k": anime_name}
        resp = await client.get(search_url, params=params,
                                headers=HEADERS, timeout=15)
        if resp.status_code != 200:
            log.error(f"TokyoInsider search failed: {resp.status_code}")
            return results

        soup = BeautifulSoup(resp.text, "lxml")
        anime_links = soup.select("a[href*='/anime/']")
        if not anime_links:
            log.warning("No anime found on TokyoInsider")
            return results

        for link in anime_links:
            href = link.get("href", "")
            text = link.get_text(strip=True).lower()
            if anime_name.lower() in text and "/anime/" in href:
                anime_url = "https://www.tokyoinsider.com" + href
                break
        else:
            anime_url = "https://www.tokyoinsider.com" + anime_links[0].get("href", "")
            if not anime_url.endswith(".html"):
                return results

        log.info(f"Found anime page: {anime_url}")

        ep_resp = await client.get(anime_url, headers=HEADERS, timeout=15)
        ep_soup = BeautifulSoup(ep_resp.text, "lxml")

        dl_links = ep_soup.select("a.download-link, a[href*='download'], td.download a, a[href*='/episode/']")
        for dl in dl_links:
            text = dl.get_text(strip=True)
            href = dl.get("href", "")
            ep_match = re.search(r'(\d+)', text)
            if not ep_match:
                continue
            ep_num = int(ep_match.group(1))
            if ep_start <= ep_num <= ep_end:
                ep_url = href if href.startswith("http") else "https://www.tokyoinsider.com" + href
                results.append({
                    "episode": ep_num,
                    "page_url": ep_url,
                    "name": f"{anime_name} Episode {ep_num}",
                    "source": "tokyoinsider",
                    "is_batch": False,
                })

        log.info(f"TokyoInsider: {len(results)} episodes in range {ep_start}-{ep_end}")
    except Exception as e:
        log.error(f"TokyoInsider error: {e}")
    return results


async def get_nyaa_episodes(
        anime_name: str,
        ep_start: int,
        ep_end: int,
        client: httpx.AsyncClient,
        quality: str = "1080p") -> list:
    """Search Nyaa for specific episode range. Batch if large range, individual otherwise."""
    results = []

    if ep_end - ep_start >= 12:
        results = await _nyaa_batch_search(anime_name, ep_start, ep_end, client)
        if results:
            return results

    for ep in range(ep_start, ep_end + 1):
        ep_str = f"{ep:02d}"
        query = f"{anime_name} {ep_str} {quality}"
        url = (f"https://nyaa.si/?f=0&c=1_0"
               f"&q={quote_plus(query)}"
               f"&s=seeders&o=desc")

        try:
            resp = await client.get(url, headers=HEADERS, timeout=12)
            if resp.status_code != 200:
                continue
            soup = BeautifulSoup(resp.text, "lxml")
            rows = soup.select("table.torrent-list tbody tr")[:5]

            found = False
            for row in rows:
                cells = row.select("td")
                if len(cells) < 8:
                    continue
                name_el = row.select_one("td:nth-child(2) a:not(.comments)")
                name = name_el.get_text(strip=True) if name_el else ""
                if not name:
                    continue

                if ep_str not in name and f"- {ep}" not in name and f" {ep} " not in name:
                    continue

                links = cells[2].select("a")
                magnet = ""
                for l_ in links:
                    h = l_.get("href", "")
                    if h.startswith("magnet:"):
                        magnet = h
                        break

                seeders = int(cells[5].get_text(strip=True) or 0)
                if magnet and seeders > 0:
                    results.append({
                        "episode": ep,
                        "name": name,
                        "magnet": magnet,
                        "seeders": seeders,
                        "is_batch": False,
                        "source": "nyaa",
                    })
                    found = True
                    break

            if not found:
                results.append({
                    "episode": ep,
                    "name": f"{anime_name} Episode {ep}",
                    "magnet": "",
                    "seeders": 0,
                    "is_batch": False,
                    "source": "nyaa",
                    "error": "not found",
                })
        except Exception as e:
            log.error(f"Nyaa ep {ep} error: {e}")
            results.append({
                "episode": ep,
                "name": f"{anime_name} Episode {ep}",
                "magnet": "", "seeders": 0,
                "is_batch": False, "source": "nyaa",
                "error": str(e),
            })

        await asyncio.sleep(0.4)

    return results


async def _nyaa_batch_search(
        anime_name: str,
        ep_start: int,
        ep_end: int,
        client: httpx.AsyncClient) -> list:
    """Search Nyaa for batch/season packs covering the episode range."""
    results = []
    searches = [
        f"{anime_name} batch",
        f"{anime_name} complete",
        f"{anime_name} {ep_start}-{ep_end}",
    ]

    for search in searches:
        url = (f"https://nyaa.si/?f=0&c=1_0"
               f"&q={quote_plus(search)}"
               f"&s=seeders&o=desc")
        try:
            resp = await client.get(url, headers=HEADERS, timeout=15)
            if resp.status_code != 200:
                continue
            soup = BeautifulSoup(resp.text, "lxml")
            rows = soup.select("table.torrent-list tbody tr")[:10]

            for row in rows:
                cells = row.select("td")
                if len(cells) < 8:
                    continue
                name_el = row.select_one("td:nth-child(2) a:not(.comments)")
                name = name_el.get_text(strip=True) if name_el else ""
                if not name or not _detect_batch(name):
                    continue
                links = cells[2].select("a")
                magnet = ""
                for l_ in links:
                    h = l_.get("href", "")
                    if h.startswith("magnet:"):
                        magnet = h
                        break
                seeders = int(cells[5].get_text(strip=True) or 0)
                if magnet and seeders > 0:
                    results.append({
                        "episode": f"{ep_start}-{ep_end}",
                        "name": name,
                        "magnet": magnet,
                        "seeders": seeders,
                        "is_batch": True,
                        "source": "nyaa_batch",
                    })
        except Exception as e:
            log.error(f"Nyaa batch search error: {e}")

        if results:
            break

    return results


async def send_to_qbittorrent(
        magnet: str,
        category: str = "anime",
        save_path: str = "") -> bool:
    """Send magnet link to qBittorrent."""
    try:
        async with httpx.AsyncClient() as client:
            data = {
                "urls": magnet,
                "category": category,
                "savepath": save_path or SAVE_PATHS.get(category, SAVE_PATHS.get("other", "/downloads")),
                "autoTMM": "false",
            }
            resp = await client.post(
                f"{QBIT_URL}/api/v2/torrents/add",
                data=data, timeout=QBIT_TIMEOUT)
            return "ok" in resp.text.lower()
    except Exception as e:
        log.error(f"qBittorrent add error: {e}")
        return False


async def batch_download(
        name: str,
        ep_start: int,
        ep_end: int,
        category: str = "anime",
        quality: str = "1080p",
        source: str = "nyaa") -> dict:
    """Main batch download function."""
    result = {
        "success": True,
        "name": name,
        "ep_start": ep_start,
        "ep_end": ep_end,
        "found": [],
        "queued": 0,
        "failed": 0,
        "skipped": 0,
    }

    async with httpx.AsyncClient() as client:
        if source == "tokyoinsider":
            episodes = await get_tokyo_insider_episodes(
                name, ep_start, ep_end, client)
        else:
            episodes = await get_nyaa_episodes(
                name, ep_start, ep_end, client, quality)

        if not episodes:
            result["success"] = False
            result["message"] = "No episodes found"
            return result

        result["found"] = episodes

        for ep in episodes:
            magnet = ep.get("magnet", "")
            if not magnet:
                result["skipped"] += 1
                continue

            ok = await send_to_qbittorrent(magnet, category)
            if ok:
                result["queued"] += 1
            else:
                result["failed"] += 1

        total = ep_end - ep_start + 1
        result["message"] = (
            f"Requested {total} episodes → "
            f"Found {len(episodes)}, Queued {result['queued']}, "
            f"Failed {result['failed']}, Skipped {result['skipped']}"
        )

    return result
