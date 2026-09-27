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

def on_alarm(a: dict):
    if a["severity"] not in ("HIGH", "CRITICAL"):
        return
    wo = {"wo_id": new_id("WO"), "alarm_id": a["alarm_id"], "asset_id": a["asset_id"], "priority": 1 if a["severity"] == "CRITICAL" else 2,
          "description": f"{a['rule']} on {a['tag']}: {a['value']:.2f} vs {a['threshold']:.2f}", "status": "DRAFT"}
    with db_conn() as c:
        c.execute("""insert into workorders(wo_id, alarm_id, asset_id, priority, description, status)
                     values (%(wo_id)s, %(alarm_id)s, %(asset_id)s, %(priority)s, %(description)s, %(status)s)
                     on conflict (alarm_id) do nothing""", wo)
    publish(os.getenv("TOPIC_WO_DRAFTS", "workorder-drafts"), wo)

@app.on_event("startup")
def startup():
    with db_conn() as c:
        c.execute("""create table if not exists workorders(wo_id text primary key, alarm_id text unique, asset_id text,
          priority int, description text, status text, approved_by text, sap_notification text, created_at timestamptz default now())""")
    subscribe(os.getenv("SUB_ALARMS", "alarms-workorder-service"), on_alarm)

@app.get("/ready")
def ready():
    if not db_ready(): raise HTTPException(503, "db")
    return {"ready": True}

@app.post("/workorders/{wo_id}/approve")
def approve(wo_id: str, request: Request):
    """Human-in-the-loop: an engineer approves the draft before it becomes a SAP PM notification."""
    user = request.headers.get("x-goog-authenticated-user-email", "unknown").replace("accounts.google.com:", "")
    sap_id = f"SAP-{new_id('N')[2:]}"  # stub: replace with SAP PM API (OData) call via erp-integration project
    with db_conn() as c:
        r = c.execute("update workorders set status='APPROVED', approved_by=%s, sap_notification=%s where wo_id=%s and status='DRAFT' returning wo_id",
                      (user, sap_id, wo_id)).fetchone()
    if not r: raise HTTPException(409, "not in DRAFT")
    return {"wo_id": wo_id, "sap_notification": sap_id}
