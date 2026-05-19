"""Shared utilities for all scrapers"""
import re


def detect_quality(name: str) -> str:
    n = name.upper()
    if "2160P" in n or "4K" in n or "UHD" in n:
        return "4K"
    if "1080P" in n or "FHD" in n:
        return "1080p"
    if "720P" in n:
        return "720p"
    if "480P" in n:
        return "480p"
    if "BLURAY" in n or "BLU-RAY" in n:
        return "BluRay"
    if "WEBRIP" in n or "WEB-DL" in n or "WEB " in n:
        return "WEB"
    if "HDTV" in n:
        return "HDTV"
    if "HDR" in n:
        return "HDR"
    return "Unknown"


def parse_size(size_str: str) -> int:
    """Parse size string like '1.2 GB' into bytes."""
    if not size_str:
        return 0
    m = re.search(r'([\d.]+)\s*(TB|GB|MB|KB|GiB|MiB|KiB)', size_str, re.I)
    if not m:
        return 0
    n = float(m.group(1))
    u = m.group(2).upper()
    return int(n * {
        "TB": 10**12, "GB": 10**9, "MB": 10**6, "KB": 10**3,
        "GIB": 2**30, "MIB": 2**20, "KIB": 2**10,
    }.get(u, 0))


def detect_batch(name: str, size: int = 0) -> bool:
    name_upper = name.upper()
    return any(kw in name_upper for kw in [
        "BATCH", "COMPLETE", "SEASON", "S0", "PACK", "(001-",
        "EP01-", "BD BOX", "COLLECTION",
    ]) or size > 2 * 1024**3


def format_size(size: int) -> str:
    if size < 1e6:
        return f"{size/1024:.0f} KB"
    if size < 1e9:
        return f"{size/1024/1024:.0f} MB"
    return f"{size/1024/1024/1024:.2f} GB"
