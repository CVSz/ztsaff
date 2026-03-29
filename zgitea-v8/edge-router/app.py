import asyncio
import os
import time
from dataclasses import dataclass
from typing import Dict, List, Optional

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, RedirectResponse


@dataclass
class Region:
    name: str
    gateway_url: str
    health_url: str
    latitude: float
    longitude: float


REGIONS: List[Region] = [
    Region("region-a", os.getenv("REGION_A_GATEWAY", "http://region-a-gateway:8080"), os.getenv("REGION_A_HEALTH", "http://region-a-gateway:8080/health"), 37.7749, -122.4194),
    Region("region-b", os.getenv("REGION_B_GATEWAY", "http://region-b-gateway:8080"), os.getenv("REGION_B_HEALTH", "http://region-b-gateway:8080/health"), 40.7128, -74.0060),
    Region("region-c", os.getenv("REGION_C_GATEWAY", "http://region-c-gateway:8080"), os.getenv("REGION_C_HEALTH", "http://region-c-gateway:8080/health"), 51.5074, -0.1278),
]

HEALTH_TTL_SEC = int(os.getenv("HEALTH_TTL_SEC", "5"))
health_cache: Dict[str, Dict[str, float]] = {}
app = FastAPI(title="ZGitea Edge Router", version="8.0")


def _distance_score(client_lat: float, client_lon: float, region: Region) -> float:
    return (client_lat - region.latitude) ** 2 + (client_lon - region.longitude) ** 2


def _geoip_hint(request: Request) -> Optional[tuple[float, float]]:
    header = request.headers.get("x-geo-coordinates", "")
    if not header:
        return None
    try:
        lat, lon = header.split(",", 1)
        return float(lat.strip()), float(lon.strip())
    except ValueError:
        return None


async def _probe(region: Region) -> Dict[str, float]:
    now = time.time()
    cached = health_cache.get(region.name)
    if cached and now - cached["timestamp"] < HEALTH_TTL_SEC:
        return cached

    started = time.perf_counter()
    healthy = 0.0
    latency_ms = 99999.0
    try:
        async with httpx.AsyncClient(timeout=1.8, follow_redirects=False) as client:
            response = await client.head(region.health_url)
            if response.status_code < 500:
                healthy = 1.0
            latency_ms = (time.perf_counter() - started) * 1000
    except Exception:
        pass

    measurement = {"healthy": healthy, "latency_ms": latency_ms, "timestamp": now}
    health_cache[region.name] = measurement
    return measurement


async def choose_region(request: Request) -> Region:
    probes = await asyncio.gather(*[_probe(r) for r in REGIONS])
    candidate_regions = [r for r, p in zip(REGIONS, probes) if p["healthy"] == 1.0]

    if not candidate_regions:
        raise HTTPException(status_code=503, detail="No healthy regions available")

    geo_hint = _geoip_hint(request)
    if geo_hint:
        lat, lon = geo_hint
        by_geo = sorted(candidate_regions, key=lambda r: _distance_score(lat, lon, r))
        best = by_geo[0]
        best_probe = health_cache[best.name]
        if best_probe["latency_ms"] <= 400:
            return best

    return min(candidate_regions, key=lambda r: health_cache[r.name]["latency_ms"])


@app.get("/health")
async def health() -> JSONResponse:
    probes = await asyncio.gather(*[_probe(r) for r in REGIONS])
    status = {r.name: p for r, p in zip(REGIONS, probes)}
    all_down = all(p["healthy"] == 0.0 for p in probes)
    return JSONResponse(status_code=503 if all_down else 200, content=status)


@app.api_route("/route/{path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
async def route(path: str, request: Request):
    region = await choose_region(request)
    target = f"{region.gateway_url}/{path}"
    if request.method == "GET":
        return RedirectResponse(target, status_code=307)

    body = await request.body()
    async with httpx.AsyncClient(timeout=20) as client:
        forwarded = await client.request(
            request.method,
            target,
            headers={k: v for k, v in request.headers.items() if k.lower() != "host"},
            content=body,
        )
    return JSONResponse(status_code=forwarded.status_code, content=forwarded.json())
