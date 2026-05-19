"""YTS scraper — movies via official REST API"""
import httpx
from urllib.parse import quote_plus
from .utils import detect_quality
import logging

log = logging.getLogger(__name__)

HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0",
}

TRACKERS = (
    "&tr=udp://open.demonii.com:1337/announce"
    "&tr=udp://tracker.openbittorrent.com:80"
)


async def scrape(query: str, client: httpx.AsyncClient, timeout: int = 15, **kwargs) -> list:
    results = []
    try:
        resp = await client.get(
            "https://yts.mx/api/v2/list_movies.json",
            params={"query_term": query, "sort_by": "seeds", "order_by": "desc", "limit": 20},
            headers=HEADERS,
            timeout=timeout,
        )
        if resp.status_code != 200:
            return results
        movies = resp.json().get("data", {}).get("movies", []) or []
        for movie in movies:
            for torrent in movie.get("torrents", []):
                quality = torrent.get("quality", "")
                hash_ = torrent.get("hash", "")
                magnet = (f"magnet:?xt=urn:btih:{hash_}"
                          f"&dn={quote_plus(movie['title'])}{TRACKERS}")
                results.append({
                    "source": "yts",
                    "source_icon": "🎬",
                    "name": f"{movie['title']} ({movie.get('year', '')}) [{quality}]",
                    "magnet": magnet,
                    "torrent_link": torrent.get("url", ""),
                    "size": torrent.get("size", ""),
                    "date": torrent.get("date_uploaded", ""),
                    "seeders": torrent.get("seeds", 0),
                    "leechers": torrent.get("peers", 0),
                    "quality": quality,
                    "category": "movies",
                    "trusted": True,
                    "imdb_rating": movie.get("rating", ""),
                    "poster": movie.get("medium_cover_image", ""),
                })
    except Exception as e:
        log.error(f"YTS error: {e}")
    return results
