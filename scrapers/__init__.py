"""
verticalmedia scrapers
Each module exposes a scrape(query, client, **kwargs) coroutine.
"""
from . import nyaa, piratebay, animetosho, yts, knaben, eztv, prowlarr, solidtorrents
from .utils import detect_quality, parse_size, detect_batch

SOURCES = {
    "nyaa": nyaa,
    "piratebay": piratebay,
    "animetosho": animetosho,
    "yts": yts,
    "knaben": knaben,
    "eztv": eztv,
    "prowlarr": prowlarr,
    "solidtorrents": solidtorrents,
}
