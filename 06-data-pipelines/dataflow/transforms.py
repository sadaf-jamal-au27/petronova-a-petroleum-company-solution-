"""Pure transform logic for the telemetry pipeline (unit-testable without Beam)."""
import json
from datetime import datetime

MAX_TS = 10**13
# Default engineering limits per measurement; asset-registry limits override via side input
LIMITS = {"vib_de_mm_s": 7.1, "bearing_temp_c": 95.0, "disch_press_bar": 55.0, "flow_m3_h": 1200.0}

def parse(msg: bytes) -> dict:
    d = json.loads(msg)
    d["ts_ms"] = int(datetime.fromisoformat(d["ts"]).timestamp() * 1000)
    return d

def dedupe_key(d: dict) -> str:
    """Edges replay buffered batches after link loss; (tag, timestamp) identifies a point."""
    return f"{d['tag']}|{d['ts_ms']}"

def measurement(tag: str) -> str:
    parts = tag.split(".")
    return parts[3] if len(parts) > 3 else parts[-1]

def anomaly(d: dict, limits: dict | None = None):
    lim = (limits or LIMITS).get(measurement(d["tag"]))
    if lim is None or d.get("quality", "GOOD") == "BAD":
        return None
    if d["value"] > lim:
        return {"site": d["site"], "asset_id": d["asset_id"], "tag": d["tag"], "value": d["value"],
                "threshold": lim, "rule": f"{measurement(d['tag'])}_hi", "ts": d["ts"]}
    return None

def bigtable_row(d: dict) -> tuple[bytes, dict]:
    key = f"{d['asset_id']}#{d['tag']}#{MAX_TS - d['ts_ms']:013d}".encode()
    return key, {"m:v": str(d["value"]).encode(), "q:q": d.get("quality", "GOOD").encode()}

def bq_row(d: dict) -> dict:
    return {"ts": d["ts"], "site": d["site"], "asset_id": d["asset_id"], "tag": d["tag"], "value": d["value"],
            "unit": d.get("unit"), "quality": d.get("quality"), "ingest_ts": d.get("ingest_ts"), "seq": d.get("seq")}
