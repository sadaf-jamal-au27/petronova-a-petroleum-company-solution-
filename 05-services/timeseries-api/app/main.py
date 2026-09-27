import os, time
from fastapi import FastAPI, HTTPException, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
from .common import LATENCY, REQUESTS, SERVICE, db_conn, db_ready, log, new_id, now, publish, subscribe

app = FastAPI(title=SERVICE)

@app.middleware("http")
async def metrics_mw(request: Request, call_next):
    start = time.time(); resp = await call_next(request)
    path = request.scope.get("route").path if request.scope.get("route") else "unmatched"
    REQUESTS.labels(SERVICE, path, resp.status_code).inc()
    LATENCY.labels(SERVICE, path).observe(time.time() - start)
    return resp

@app.get("/healthz")
def healthz():
    return {"status": "ok"}

@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

from datetime import datetime
from google.cloud import bigtable
from google.cloud.bigtable.row_set import RowSet

MAX_TS = 10**13
_table = None

def table():
    global _table
    if _table is None:
        client = bigtable.Client(project=os.environ["BIGTABLE_PROJECT"])
        _table = client.instance(os.environ["BIGTABLE_INSTANCE"]).table("telemetry", app_profile_id=os.getenv("BIGTABLE_APP_PROFILE", "serving"))
    return _table

def row_key(asset_id: str, tag: str, ts_ms: int) -> bytes:
    # Reverse timestamp so the newest points sort first for an asset/tag
    return f"{asset_id}#{tag}#{MAX_TS - ts_ms:013d}".encode()

def key_range(asset_id: str, tag: str, start_ms: int, end_ms: int) -> tuple[bytes, bytes]:
    return row_key(asset_id, tag, end_ms), row_key(asset_id, tag, start_ms)

@app.get("/ready")
def ready():
    return {"ready": True}

@app.get("/series")
def series(asset_id: str, tag: str, start: str, end: str, limit: int = 5000):
    s = int(datetime.fromisoformat(start).timestamp() * 1000); e = int(datetime.fromisoformat(end).timestamp() * 1000)
    if e <= s or e - s > 31 * 86400 * 1000:
        raise HTTPException(422, "range must be positive and at most 31 days")
    lo, hi = key_range(asset_id, tag, s, e)
    rs = RowSet(); rs.add_row_range_from_keys(start_key=lo, end_key=hi, end_inclusive=True)
    out = []
    for row in table().read_rows(row_set=rs, limit=min(limit, 20000)):
        cell = row.cells["m"][b"v"][0]
        ts_ms = MAX_TS - int(row.row_key.decode().split("#")[-1])
        out.append({"ts": ts_ms, "v": float(cell.value.decode())})
    return {"asset_id": asset_id, "tag": tag, "points": list(reversed(out))}
