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

import json, pathlib, threading, ssl
import jsonschema
import paho.mqtt.client as mqtt
from prometheus_client import Counter

SCHEMA = json.loads((pathlib.Path(__file__).parent / "telemetry-batch.schema.json").read_text())
TOPIC = os.getenv("TOPIC_TELEMETRY_RAW", "telemetry-raw")
BATCHES = Counter("petronova_bridge_batches_total", "Batches from edges", ["site", "result"])
state = {"connected": False}

def to_pubsub(batch: dict) -> list[dict]:
    """Validate an edge batch and flatten it into Pub/Sub messages (one per point)."""
    jsonschema.validate(batch, SCHEMA)
    out = []
    for p in batch["points"]:
        out.append({"site": batch["site"], "edge_id": batch["edge_id"], "seq": batch["seq"],
                    "replayed": batch.get("replayed", False), "asset_id": p["asset_id"], "tag": p["tag"],
                    "ts": p["ts"], "value": p["v"], "unit": p.get("u", ""), "quality": p.get("q", "GOOD"),
                    "ingest_ts": now()})
    return out

def on_message(client, userdata, msg):
    site = msg.topic.split("/")[1] if "/" in msg.topic else "unknown"
    try:
        batch = json.loads(msg.payload)
        for m in to_pubsub(batch):
            publish(TOPIC, m, site=m["site"], asset_id=m["asset_id"])
        BATCHES.labels(site, "ok").inc()
    except Exception as e:  # noqa: BLE001
        BATCHES.labels(site, "rejected").inc()
        log.warning(f"rejected batch from {site}: {e}")

def start_mqtt():
    c = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=f"bridge-{os.getenv('HOSTNAME', 'local')}")
    if os.getenv("MQTT_TLS", "true") == "true":
        c.tls_set(ca_certs=os.getenv("MQTT_CA", "/certs/ca.crt"), certfile=os.getenv("MQTT_CERT", "/certs/tls.crt"),
                  keyfile=os.getenv("MQTT_KEY", "/certs/tls.key"), tls_version=ssl.PROTOCOL_TLS_CLIENT)
    c.on_connect = lambda cl, u, f, rc, p=None: (state.update(connected=True), cl.subscribe("petronova/+/telemetry", qos=1))
    c.on_disconnect = lambda *a: state.update(connected=False)
    c.on_message = on_message
    c.connect(os.getenv("MQTT_HOST", "mosquitto"), int(os.getenv("MQTT_PORT", "8883")))
    threading.Thread(target=c.loop_forever, daemon=True).start()

@app.on_event("startup")
def startup():
    if os.getenv("MQTT_ENABLED", "true") == "true":
        start_mqtt()

@app.get("/ready")
def ready():
    if os.getenv("MQTT_ENABLED", "true") == "true" and not state["connected"]:
        raise HTTPException(503, "mqtt not connected")
    return {"ready": True}
