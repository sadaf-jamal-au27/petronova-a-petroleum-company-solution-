"""End-to-end logic test: edge batch -> bridge validation -> anomaly -> alarm -> work order draft.
Cloud dependencies (Pub/Sub, Cloud SQL, Bigtable) are mocked."""
import importlib, pathlib, sys, tempfile
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[1]

def load(svc):
    from prometheus_client import REGISTRY
    for c in list(REGISTRY._collector_to_names):
        try: REGISTRY.unregister(c)
        except Exception: pass
    for k in [k for k in sys.modules if k == "app" or k.startswith("app.")]: del sys.modules[k]
    sys.path.insert(0, str(ROOT / svc)); m = importlib.import_module("app.main"); sys.path.pop(0); return m

def load_edge():
    sys.path.insert(0, str(ROOT / "edge-simulator")); m = importlib.import_module("edge"); sys.path.pop(0); return m

class Cur:
    def __init__(s, row): s.row = row
    def fetchone(s): return s.row
class Conn:
    def __init__(s, row=("x",)): s.row = row; s.sql = []
    def __enter__(s): return s
    def __exit__(s, *a): pass
    def execute(s, q, *a): s.sql.append(q); return Cur(s.row)

def test_edge_buffer_store_and_forward():
    edge = load_edge()
    with tempfile.TemporaryDirectory() as d:
        b = edge.Buffer(d, max_batches=3)
        for i in range(5): b.put(edge.make_batch(i))
        assert len(b) == 3                     # capped, oldest dropped
        replay = b.drain()
        assert [x["seq"] for x in replay] == [2, 3, 4] and all(x["replayed"] for x in replay)
        assert len(b) == 0

def test_bridge_validates_and_flattens():
    edge = load_edge(); bridge = load("mqtt-bridge")
    batch = edge.make_batch(7, anomaly=True)
    msgs = bridge.to_pubsub(batch)
    assert len(msgs) == edge.N_TAGS and msgs[0]["seq"] == 7
    vib = [m for m in msgs if m["asset_id"] == "K-101" and m["tag"].endswith("vib_de_mm_s")][0]
    assert vib["value"] > 6                    # injected bearing defect
    bad = dict(batch); bad.pop("points")
    try:
        bridge.to_pubsub(bad); assert False, "schema should reject"
    except Exception:
        pass

def test_alarm_and_workorder_chain():
    published = []
    alarm = load("alarm-service")
    assert alarm.severity(9.0, 2.5) == "CRITICAL" and alarm.severity(4.0, 2.5) == "MEDIUM"
    anomaly = {"site": "hazira", "asset_id": "K-101", "tag": "hazira.u100.K-101.vib_de_mm_s", "value": 8.1, "threshold": 2.5, "rule": "vibration_hi"}
    with mock.patch.object(alarm, "db_conn", lambda: Conn()), mock.patch.object(alarm, "publish", lambda t, p, **k: published.append((t, p))):
        alarm.on_anomaly(anomaly); alarm.on_anomaly(anomaly)   # second is suppressed (flood control)
    assert len(published) == 1 and published[0][1]["severity"] == "CRITICAL"
    wo = load("workorder-service")
    with mock.patch.object(wo, "db_conn", lambda: Conn()), mock.patch.object(wo, "publish", lambda t, p, **k: published.append((t, p))):
        wo.on_alarm(published[0][1])
    assert published[-1][0] == "workorder-drafts" and published[-1][1]["status"] == "DRAFT" and published[-1][1]["priority"] == 1

def test_timeseries_row_keys_newest_first():
    ts = load("timeseries-api")
    newer, older = ts.row_key("K-101", "t", 2_000), ts.row_key("K-101", "t", 1_000)
    assert newer < older                       # reverse timestamp sorts newest first
    lo, hi = ts.key_range("K-101", "t", 1_000, 2_000)
    assert lo == newer and hi == older
