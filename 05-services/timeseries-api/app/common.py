"""Shared helpers (kept in each service so squads stay independent).
Platform keeps the canonical copy in petronova-ci-templates/python-common."""
import json, logging, os, sys, threading, time, uuid
from datetime import datetime, timezone

import psycopg
from google.cloud import pubsub_v1
from prometheus_client import Counter, Histogram

SERVICE = os.getenv("SERVICE_NAME", "service")
PROJECT_EVENTS = os.getenv("EVENTS_PROJECT", "")
REQUESTS = Counter("petronova_requests_total", "HTTP requests", ["service", "path", "code"])
LATENCY = Histogram("petronova_request_seconds", "HTTP latency", ["service", "path"])
EVENTS = Counter("petronova_events_total", "Events handled", ["service", "topic", "result"])

class JsonFormatter(logging.Formatter):
    # Structured logs for Cloud Logging. Never log credentials or commercial production figures.
    def format(self, r):
        d = {"severity": r.levelname, "message": r.getMessage(), "service": SERVICE}
        d.update(getattr(r, "extra_fields", {}))
        return json.dumps(d)

def get_logger():
    h = logging.StreamHandler(sys.stdout); h.setFormatter(JsonFormatter())
    log = logging.getLogger(SERVICE); log.handlers = [h]; log.setLevel(os.getenv("LOG_LEVEL", "INFO").upper())
    return log

log = get_logger()

def now():
    return datetime.now(timezone.utc).isoformat()

def new_id(prefix):
    return f"{prefix}-{uuid.uuid4().hex[:12]}"

def db_conn():
    # Cloud SQL Auth Proxy sidecar on localhost with IAM authn: no password needed.
    return psycopg.connect(
        host=os.getenv("DB_HOST", "127.0.0.1"), port=int(os.getenv("DB_PORT", "5432")),
        dbname=os.environ["DB_NAME"], user=os.environ["DB_USER"],
        password=os.getenv("DB_PASSWORD", ""), autocommit=True, connect_timeout=5)

def db_ready():
    try:
        with db_conn() as c:
            c.execute("select 1")
        return True
    except Exception as e:  # noqa: BLE001
        log.warning(f"db not ready: {e}")
        return False

_publisher = None
def publish(topic, payload, **attrs):
    global _publisher
    if _publisher is None:
        _publisher = pubsub_v1.PublisherClient()
    path = _publisher.topic_path(PROJECT_EVENTS, topic)
    fut = _publisher.publish(path, json.dumps(payload).encode(), source=SERVICE, **attrs)
    msg_id = fut.result(timeout=10)
    EVENTS.labels(SERVICE, topic, "published").inc()
    return msg_id

def subscribe(subscription, handler):
    """Start a background streaming pull. handler(dict) -> None; raise to nack."""
    sub = pubsub_v1.SubscriberClient()
    path = sub.subscription_path(PROJECT_EVENTS, subscription)
    def cb(msg):
        try:
            handler(json.loads(msg.data))
            msg.ack(); EVENTS.labels(SERVICE, subscription, "ok").inc()
        except Exception as e:  # noqa: BLE001
            log.error(f"handler failed on {subscription}: {e}")
            msg.nack(); EVENTS.labels(SERVICE, subscription, "error").inc()
    flow = pubsub_v1.types.FlowControl(max_messages=20)
    future = sub.subscribe(path, callback=cb, flow_control=flow)
    def run():
        while True:
            try:
                future.result()
            except Exception as e:  # noqa: BLE001
                log.error(f"subscriber stopped: {e}; restarting in 5s"); time.sleep(5)
    threading.Thread(target=run, daemon=True).start()
    log.info(f"subscribed to {subscription}")
