"""Prowlarr aggregator — queries all configured indexers"""
import httpx
from .utils import detect_quality, detect_batch, format_size
import logging

log = logging.getLogger(__name__)

INDEXER_ICONS = {
    "nyaa": "🌸", "1337x": "🏴", "piratebay": "☠️",
    "yts": "🎬", "animetosho": "🗃️", "limetorrents": "🍋",
    "rarbg": "🔴", "torrentgalaxy": "🌌",
}

CAT_MAP = {
    "movies": [2000, 2010, 2020, 2030, 2040, 2045, 2050, 2060],
    "shows":  [5000, 5010, 5020, 5030, 5040, 5045, 5050, 5060],
    "anime":  [5070, 5080],
    "all":    [],
}


async def scrape(query: str, client: httpx.AsyncClient,
                 prowlarr_url: str = "", prowlarr_key: str = "",
                 category: str = "all", timeout: int = 30,
                 batch: bool = False, **kwargs) -> list:
    results = []
    if not prowlarr_key:
        return results
    try:
        if batch:
            query = f"{query} complete season"
        params: dict = {"apikey": prowlarr_key, "query": query, "type": "search"}
        for c in CAT_MAP.get(category, []):
            params.setdefault("categories[]", []).append(c)
        resp = await client.get(
            f"{prowlarr_url}/api/v1/search",
            params=params,
            timeout=timeout,
        )
        if resp.status_code != 200 or not resp.text.strip():
            return results
        items = resp.json()
        if not isinstance(items, list):
            return results
        for item in items:
            name = item.get("title", "")
            if not name:
                continue
            size = item.get("size", 0)
            size_str = format_size(size) if isinstance(size, int) and size > 0 else str(size)
            age = item.get("age", 0)
            indexer = item.get("indexer", "")
            icon = next((v for k, v in INDEXER_ICONS.items()
                         if k.lower() in indexer.lower()), "📡")
            is_batch = detect_batch(name)
            if batch and not is_batch:
                continue
            results.append({
                "source": f"prowlarr:{indexer}",
                "source_icon": icon,
                "source_display": indexer,
                "name": name,
                "magnet": item.get("magnetUrl", ""),
                "torrent_link": item.get("downloadUrl", ""),
                "info_url": item.get("infoUrl", ""),
                "size": size_str,
                "date": f"{age}d ago" if age else "",
                "seeders": item.get("seeders", 0),
                "leechers": item.get("leechers", 0),
                "quality": detect_quality(name),
                "category": category,
                "trusted": False,
                "is_batch": is_batch,
            })
    except Exception as e:
        log.error(f"Prowlarr error: {e}")
    return results
