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

SEVERITY_BANDS = [(3.0, "CRITICAL"), (2.0, "HIGH"), (1.5, "MEDIUM"), (0.0, "LOW")]
SUPPRESS_SECONDS = int(os.getenv("SUPPRESS_SECONDS", "300"))
_last = {}

def severity(value: float, threshold: float) -> str:
    ratio = abs(value) / threshold if threshold else 0
    for limit, sev in SEVERITY_BANDS:
        if ratio >= limit:
            return sev
    return "LOW"

def should_raise(key: str, ts: float) -> bool:
    """Suppress repeated alarms for the same asset/tag within the window (alarm flood control, ISA-18.2)."""
    last = _last.get(key)
    if last and ts - last < SUPPRESS_SECONDS:
        return False
    _last[key] = ts
    return True

def on_anomaly(e: dict):
    key = f"{e['asset_id']}|{e['tag']}"
    if not should_raise(key, time.time()):
        return
    alarm = {"alarm_id": new_id("ALM"), "raised_at": now(), "site": e["site"], "asset_id": e["asset_id"],
             "tag": e["tag"], "severity": severity(e["value"], e["threshold"]), "rule": e.get("rule", "threshold"),
             "value": float(e["value"]), "threshold": float(e["threshold"])}
    with db_conn() as c:
        c.execute("""insert into alarms(alarm_id, raised_at, site, asset_id, tag, severity, rule, value, threshold)
                     values (%(alarm_id)s, %(raised_at)s, %(site)s, %(asset_id)s, %(tag)s, %(severity)s, %(rule)s, %(value)s, %(threshold)s)""", alarm)
    publish(os.getenv("TOPIC_ALARMS", "alarms"), alarm, severity=alarm["severity"])
    log.info("alarm raised", extra={"extra_fields": {"alarm_id": alarm["alarm_id"], "severity": alarm["severity"], "asset_id": alarm["asset_id"]}})

@app.on_event("startup")
def startup():
    with db_conn() as c:
        c.execute("""create table if not exists alarms(alarm_id text primary key, raised_at timestamptz, site text,
          asset_id text, tag text, severity text, rule text, value double precision, threshold double precision,
          acknowledged_by text, acknowledged_at timestamptz)""")
    subscribe(os.getenv("SUB_ANOMALY", "telemetry-anomaly-alarm-service"), on_anomaly)

@app.get("/ready")
def ready():
    if not db_ready(): raise HTTPException(503, "db")
    return {"ready": True}

@app.get("/alarms")
def list_alarms(site: str | None = None, limit: int = 100):
    with db_conn() as c:
        rows = c.execute("""select alarm_id, raised_at, site, asset_id, tag, severity, value, threshold, acknowledged_by
                            from alarms where (%s::text is null or site = %s) order by raised_at desc limit %s""",
                         (site, site, min(limit, 500))).fetchall()
    keys = ["alarm_id", "raised_at", "site", "asset_id", "tag", "severity", "value", "threshold", "acknowledged_by"]
    return [dict(zip(keys, [str(x) if i == 1 else x for i, x in enumerate(r)])) for r in rows]

@app.post("/alarms/{alarm_id}/ack")
def ack(alarm_id: str, request: Request):
    user = request.headers.get("x-goog-authenticated-user-email", "unknown").replace("accounts.google.com:", "")
    with db_conn() as c:
        r = c.execute("update alarms set acknowledged_by=%s, acknowledged_at=now() where alarm_id=%s returning alarm_id", (user, alarm_id)).fetchone()
    if not r: raise HTTPException(404, "not found")
    return {"alarm_id": alarm_id, "acknowledged_by": user}
