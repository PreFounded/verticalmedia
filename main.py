#!/usr/bin/env python3
"""verticalmedia — self-hosted torrent search and download manager"""
from fastapi import FastAPI, Query, Request
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse, JSONResponse
import httpx, asyncio, re, logging, shutil
from bs4 import BeautifulSoup
from pathlib import Path

from config import (
    QBIT_URL, PROWLARR_URL, PROWLARR_KEY,
    TMDB_KEY, SAVE_PATHS, HOST, PORT,
    SCRAPER_TIMEOUT, QBIT_TIMEOUT,
)

from scrapers import nyaa, piratebay, animetosho, yts, knaben, eztv, solidtorrents
from scrapers import prowlarr as prowlarr_scraper
from scrapers.utils import detect_quality, parse_size, detect_batch

app = FastAPI(title="verticalmedia", version="1.0.0")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0",
    "Accept-Language": "en-US,en;q=0.9",
}

log.info(f"verticalmedia starting — qBit: {QBIT_URL} | "
         f"Prowlarr: {'configured' if PROWLARR_KEY else 'not configured'}")

# ━━━ CONFIG / HEALTH ━━━

@app.get("/api/config")
async def get_config():
    return {
        "qbit_url": QBIT_URL,
        "prowlarr_url": PROWLARR_URL,
        "prowlarr_connected": bool(PROWLARR_KEY),
        "tmdb_connected": bool(TMDB_KEY),
        "save_paths": SAVE_PATHS,
    }

@app.post("/api/test-connection")
async def test_connection(request: Request):
    data = await request.json()
    conn_type = data.get("type", "")
    url = data.get("url", "")
    key = data.get("key", "")
    try:
        async with httpx.AsyncClient() as c:
            if conn_type == "qbit":
                r = await c.get(f"{url}/api/v2/app/version", timeout=5)
                return {"ok": r.status_code == 200, "detail": r.text[:100]}
            elif conn_type == "prowlarr":
                r = await c.get(f"{url}/api/v1/indexer",
                                headers={"X-Api-Key": key}, timeout=5)
                return {"ok": r.status_code == 200}
    except Exception as e:
        return {"ok": False, "detail": str(e)}
    return {"ok": False}

@app.get("/health")
async def health():
    qbit_ok = False
    try:
        async with httpx.AsyncClient() as c:
            r = await c.get(f"{QBIT_URL}/api/v2/app/version", timeout=3)
            qbit_ok = r.status_code == 200
    except Exception:
        pass
    return {
        "status": "ok",
        "version": "1.0.0",
        "qbit": "connected" if qbit_ok else "disconnected",
        "prowlarr": "configured" if PROWLARR_KEY else "not configured",
    }

# ━━━ TMDB ENRICHMENT ━━━

async def enrich_with_tmdb(results: list, client: httpx.AsyncClient) -> list:
    for result in results:
        if result.get("poster"):
            continue
        if result.get("category") not in ("movies", "general"):
            continue
        name = result["name"]
        clean = re.sub(r'\[.*?\]|\(.*?\)', '', name).strip()
        clean = re.sub(r'\b(BluRay|WEBRip|x264|x265|HEVC|AAC|HDR)\b', '', clean, flags=re.I).strip()
        if not clean or len(clean) < 3:
            continue
        try:
            resp = await client.get(
                "https://api.themoviedb.org/3/search/movie",
                params={"api_key": TMDB_KEY, "query": clean[:50], "include_adult": "false"},
                timeout=5,
            )
            if resp.status_code == 200:
                movies = resp.json().get("results", [])
                if movies:
                    m = movies[0]
                    poster = m.get("poster_path", "")
                    if poster:
                        result["poster"] = f"https://image.tmdb.org/t/p/w92{poster}"
                    result["tmdb_rating"] = m.get("vote_average", 0)
                    result["tmdb_year"] = (m.get("release_date", "") or "")[:4]
        except Exception:
            pass
    return results

# ━━━ SEARCH ━━━

@app.get("/api/search")
async def search(
    q: str = Query(..., min_length=1),
    category: str = "all",
    sources: str = "prowlarr,nyaa,yts,animetosho,piratebay,knaben,solidtorrents",
    sort: str = "seeders",
    batch_only: bool = False,
):
    source_list = [s.strip() for s in sources.split(",")]
    prowlarr_kwargs = dict(
        prowlarr_url=PROWLARR_URL,
        prowlarr_key=PROWLARR_KEY,
        category=category,
        timeout=30,
    )

    async with httpx.AsyncClient() as client:
        tasks = []
        if batch_only:
            if "prowlarr" in source_list:
                tasks.append(prowlarr_scraper.scrape(q, client, batch=True, **prowlarr_kwargs))
            if "nyaa" in source_list and category in ("all", "anime"):
                tasks.append(nyaa.scrape_batch(q, client, SCRAPER_TIMEOUT))
                tasks.append(nyaa.scrape(q, client, SCRAPER_TIMEOUT, batch=True))
            if "eztv" in source_list and category in ("all", "shows"):
                tasks.append(eztv.scrape(q, client, SCRAPER_TIMEOUT))
            if "solidtorrents" in source_list:
                tasks.append(solidtorrents.scrape(f"{q} complete season", client, SCRAPER_TIMEOUT))
        else:
            if "prowlarr" in source_list:
                tasks.append(prowlarr_scraper.scrape(q, client, **prowlarr_kwargs))
            if "nyaa" in source_list and category in ("all", "anime"):
                tasks.append(nyaa.scrape(q, client, SCRAPER_TIMEOUT))
            if "eztv" in source_list and category in ("all", "shows"):
                tasks.append(eztv.scrape(q, client, SCRAPER_TIMEOUT))
            if "animetosho" in source_list and category in ("all", "anime"):
                tasks.append(animetosho.scrape(q, client, SCRAPER_TIMEOUT))
            if "yts" in source_list and category in ("all", "movies"):
                tasks.append(yts.scrape(q, client, SCRAPER_TIMEOUT))
            if "piratebay" in source_list:
                tasks.append(piratebay.scrape(q, client, SCRAPER_TIMEOUT))
            if "knaben" in source_list:
                tasks.append(knaben.scrape(q, client, SCRAPER_TIMEOUT))
            if "solidtorrents" in source_list:
                tasks.append(solidtorrents.scrape(q, client, SCRAPER_TIMEOUT))

        all_results = await asyncio.gather(*tasks, return_exceptions=True)

    results = []
    seen = set()
    for batch in all_results:
        if isinstance(batch, list):
            for r in batch:
                key = r["name"][:60].lower()
                if key not in seen:
                    seen.add(key)
                    results.append(r)

    if category in ("all", "movies") and not batch_only:
        async with httpx.AsyncClient() as enrich_client:
            results = await enrich_with_tmdb(results, enrich_client)

    if batch_only:
        results.sort(key=lambda x: (parse_size(x.get("size", "")), x.get("seeders", 0)), reverse=True)
    elif sort == "seeders":
        results.sort(key=lambda x: x.get("seeders", 0), reverse=True)
    elif sort == "size":
        results.sort(key=lambda x: parse_size(x.get("size", "")), reverse=True)

    return {"query": q, "category": category, "count": len(results), "results": results, "batch_only": batch_only}

# ━━━ INDEXERS ━━━

@app.get("/api/indexers")
async def get_indexers():
    if not PROWLARR_KEY:
        return {"count": 0, "indexers": []}
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get(
                f"{PROWLARR_URL}/api/v1/indexer",
                headers={"X-Api-Key": PROWLARR_KEY},
                timeout=10,
            )
            if resp.status_code == 200:
                indexers = resp.json()
                return {
                    "count": len(indexers),
                    "indexers": [{"id": i["id"], "name": i["name"],
                                  "protocol": i.get("protocol", ""),
                                  "enabled": i.get("enable", True)} for i in indexers],
                }
    except Exception as e:
        log.error(f"Indexers error: {e}")
    return {"count": 0, "indexers": []}

# ━━━ MAGNET FETCH ━━━

@app.get("/api/magnet")
async def get_magnet(detail_url: str = Query(...)):
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get(detail_url, headers=HEADERS,
                                    timeout=SCRAPER_TIMEOUT, follow_redirects=True)
            el = BeautifulSoup(resp.text, "lxml").select_one('a[href^="magnet:"]')
            return {"magnet": el.get("href", "") if el else ""}
    except Exception:
        return {"magnet": ""}

# ━━━ DOWNLOAD ━━━

@app.post("/api/download")
async def download(magnet: str = Query(...), category: str = Query("other")):
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.post(f"{QBIT_URL}/api/v2/torrents/add", data={
                "urls": magnet,
                "category": category,
                "savepath": SAVE_PATHS.get(category, SAVE_PATHS.get("other", "/downloads")),
                "autoTMM": "false",
            }, timeout=QBIT_TIMEOUT)
            ok = "ok" in resp.text.lower()
            return {"success": ok, "message": "Added" if ok else resp.text.strip()}
    except Exception as e:
        return {"success": False, "message": str(e)}

# ━━━ DOWNLOADS STATUS ━━━

@app.get("/api/downloads")
async def get_downloads():
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get(f"{QBIT_URL}/api/v2/torrents/info", timeout=5)
            if resp.status_code == 200:
                return {"torrents": [{
                    "name": t["name"],
                    "progress": round(t["progress"] * 100, 1),
                    "dlspeed": t["dlspeed"],
                    "state": t["state"],
                    "size": t["total_size"],
                    "category": t.get("category", ""),
                    "eta": t.get("eta", 0),
                    "hash": t.get("hash", ""),
                } for t in resp.json()]}
    except Exception:
        pass
    return {"torrents": []}

# ━━━ LIBRARY ━━━

@app.get("/api/library")
async def get_library():
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get(f"{QBIT_URL}/api/v2/torrents/info", timeout=5)
            if resp.status_code == 200:
                return {"torrents": [{
                    "hash": t["hash"],
                    "name": t["name"],
                    "progress": round(t["progress"] * 100, 1),
                    "dlspeed": t["dlspeed"],
                    "upspeed": t.get("upspeed", 0),
                    "state": t["state"],
                    "size": t["total_size"],
                    "downloaded": t.get("completed", 0),
                    "category": t.get("category", ""),
                    "eta": t.get("eta", 0),
                    "save_path": t.get("save_path", ""),
                    "added_on": t.get("added_on", 0),
                    "completion_on": t.get("completion_on", 0),
                    "ratio": round(t.get("ratio", 0), 2),
                    "num_seeds": t.get("num_seeds", 0),
                    "num_leechs": t.get("num_leechs", 0),
                } for t in resp.json()]}
    except Exception as e:
        log.error(f"Library error: {e}")
    return {"torrents": []}

@app.delete("/api/torrent/{torrent_hash}")
async def delete_torrent(torrent_hash: str, delete_files: bool = Query(False)):
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.post(f"{QBIT_URL}/api/v2/torrents/delete", data={
                "hashes": torrent_hash,
                "deleteFiles": "true" if delete_files else "false",
            }, timeout=5)
            return {"success": resp.status_code == 200}
    except Exception as e:
        return {"success": False, "message": str(e)}

@app.post("/api/torrent/{torrent_hash}/{action}")
async def torrent_action(torrent_hash: str, action: str):
    if action not in ("pause", "resume"):
        return {"success": False, "message": "Invalid action"}
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.post(
                f"{QBIT_URL}/api/v2/torrents/{action}",
                data={"hashes": torrent_hash},
                timeout=5,
            )
            return {"success": resp.status_code == 200}
    except Exception as e:
        return {"success": False, "message": str(e)}

@app.get("/api/check-downloaded")
async def check_downloaded(name: str = Query(...)):
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get(f"{QBIT_URL}/api/v2/torrents/info", timeout=5)
            if resp.status_code == 200:
                name_clean = name.lower()[:40]
                for t in resp.json():
                    if name_clean in t["name"].lower():
                        return {"exists": True, "torrent": {
                            "name": t["name"],
                            "progress": round(t["progress"] * 100, 1),
                            "state": t["state"],
                        }}
    except Exception:
        pass
    return {"exists": False}

# ━━━ STORAGE ━━━

@app.get("/api/storage")
async def get_storage():
    result: dict = {"folders": {}}
    for name, path in SAVE_PATHS.items():
        try:
            size = sum(f.stat().st_size for f in Path(path).rglob("*") if f.is_file())
            result["folders"][name] = size
        except Exception:
            result["folders"][name] = 0
    try:
        disk_path = list(SAVE_PATHS.values())[0] if SAVE_PATHS else "/"
        while not Path(disk_path).exists() and disk_path != "/":
            disk_path = str(Path(disk_path).parent)
        disk = shutil.disk_usage(disk_path)
        result.update({"total_free": disk.free, "total_used": disk.used, "total": disk.total})
    except Exception:
        pass
    return result

# ━━━ BATCH EPISODE DOWNLOAD ━━━

@app.post("/api/batch-download")
async def batch_download_endpoint(request: Request):
    data = await request.json()
    name = data.get("name", "")
    ep_start = int(data.get("ep_start", 1))
    ep_end = int(data.get("ep_end", 1))
    category = data.get("category", "anime")
    quality = data.get("quality", "1080p")
    source = data.get("source", "nyaa")

    if not name:
        return JSONResponse({"success": False, "error": "No name provided"}, 400)
    if ep_end < ep_start:
        return JSONResponse({"success": False, "error": "ep_end must be >= ep_start"}, 400)
    if ep_end - ep_start > 200:
        return JSONResponse({"success": False, "error": "Max 200 episodes per batch"}, 400)

    from scrapers.batch_downloader import batch_download
    result = await batch_download(name, ep_start, ep_end, category, quality, source)

    return {
        "success": result.get("success", True),
        "name": name,
        "requested": ep_end - ep_start + 1,
        "found": len(result.get("found", [])),
        "queued": result.get("queued", 0),
        "failed": result.get("failed", 0),
        "skipped": result.get("skipped", 0),
        "episodes": result.get("found", [])[:5],
        "message": result.get("message", ""),
    }

# ━━━ FRONTEND ━━━

app.mount("/static", StaticFiles(directory="static"), name="static")

@app.get("/")
async def root():
    with open("static/index.html") as f:
        return HTMLResponse(f.read())

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=HOST, port=PORT)
