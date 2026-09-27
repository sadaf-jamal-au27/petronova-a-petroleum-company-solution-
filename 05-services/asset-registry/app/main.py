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

@app.on_event("startup")
def startup():
    with db_conn() as c:
        c.execute("""create table if not exists assets(asset_id text primary key, site text, unit text,
          equipment_class text, description text, criticality text)""")
        c.execute("""create table if not exists tags(tag text primary key, asset_id text references assets,
          measurement text, unit text, hi_limit double precision, lo_limit double precision)""")

@app.get("/ready")
def ready():
    if not db_ready(): raise HTTPException(503, "db")
    return {"ready": True}

@app.post("/assets", status_code=201)
def upsert_asset(a: dict):
    for f in ("asset_id", "site", "equipment_class"):
        if not a.get(f): raise HTTPException(422, f"{f} required")
    with db_conn() as c:
        c.execute("""insert into assets values (%(asset_id)s, %(site)s, %(unit)s, %(equipment_class)s, %(description)s, %(criticality)s)
                     on conflict (asset_id) do update set description=excluded.description, criticality=excluded.criticality""",
                  {"unit": None, "description": None, "criticality": "C", **a})
    return {"asset_id": a["asset_id"]}

@app.get("/assets/{asset_id}")
def get_asset(asset_id: str):
    with db_conn() as c:
        r = c.execute("select asset_id, site, unit, equipment_class, description, criticality from assets where asset_id=%s", (asset_id,)).fetchone()
        tags = c.execute("select tag, measurement, unit, hi_limit, lo_limit from tags where asset_id=%s", (asset_id,)).fetchall()
    if not r: raise HTTPException(404, "not found")
    return {"asset_id": r[0], "site": r[1], "unit": r[2], "equipment_class": r[3], "description": r[4], "criticality": r[5],
            "tags": [dict(zip(["tag", "measurement", "unit", "hi_limit", "lo_limit"], t)) for t in tags]}
