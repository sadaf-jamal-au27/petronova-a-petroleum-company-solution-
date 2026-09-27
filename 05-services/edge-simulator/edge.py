"""Edge gateway simulator for the L3.5 DMZ.

Generates compressor/pump telemetry, publishes Sparkplug-style JSON batches over MQTT/TLS,
and store-and-forwards to local disk when the hybrid link is down (replayed on reconnect).
"""
import json, math, os, pathlib, random, ssl, time
from datetime import datetime, timezone

SITE = os.getenv("SITE", "hazira")
EDGE_ID = os.getenv("EDGE_ID", f"{SITE}-edge-01")
N_TAGS = int(os.getenv("TAGS", "100"))
PERIOD = float(os.getenv("PERIOD_SECONDS", "1"))
ANOMALY_ASSET = os.getenv("ANOMALY_ASSET", "K-101")

class Buffer:
    """Append-only JSONL store-and-forward buffer with a size cap (oldest dropped first)."""
    def __init__(self, directory: str, max_batches: int = 259200):  # 72 h at 1 batch/s
        self.dir = pathlib.Path(directory); self.dir.mkdir(parents=True, exist_ok=True)
        self.file = self.dir / "pending.jsonl"; self.max = max_batches
    def put(self, batch: dict):
        with self.file.open("a") as f:
            f.write(json.dumps(batch) + "\n")
        self._trim()
    def _trim(self):
        lines = self.file.read_text().splitlines()
        if len(lines) > self.max:
            self.file.write_text("\n".join(lines[-self.max:]) + "\n")
    def drain(self):
        if not self.file.exists():
            return []
        lines = [l for l in self.file.read_text().splitlines() if l.strip()]
        self.file.unlink()
        return [dict(json.loads(l), replayed=True) for l in lines]
    def __len__(self):
        return len(self.file.read_text().splitlines()) if self.file.exists() else 0

ASSETS = [("K-101", "compressor"), ("K-102", "compressor"), ("P-201", "pump"), ("P-202", "pump"), ("T-301", "turbine")]
MEAS = {"vib_de_mm_s": (2.5, "mm/s"), "bearing_temp_c": (68.0, "degC"), "disch_press_bar": (42.0, "bar"), "flow_m3_h": (850.0, "m3/h")}

def tags():
    out = []
    for i in range(N_TAGS):
        asset, _ = ASSETS[i % len(ASSETS)]
        m = list(MEAS)[i % len(MEAS)]
        out.append((asset, f"{SITE}.u100.{asset}.{m}" + (f".{i // 20}" if i >= 20 else ""), m))
    return out

def sample(asset, meas, t, anomaly=False):
    base, _ = MEAS[meas]
    v = base * (1 + 0.02 * math.sin(t / 60) + random.gauss(0, 0.01))
    if anomaly and asset == ANOMALY_ASSET and meas == "vib_de_mm_s":
        v *= 3.2  # bearing defect signature
    return round(v, 3)

def make_batch(seq: int, anomaly=False) -> dict:
    now = datetime.now(timezone.utc); t = now.timestamp()
    pts = [{"asset_id": a, "tag": tag, "ts": now.isoformat(), "v": sample(a, m, t, anomaly), "u": MEAS[m][1], "q": "GOOD"}
           for a, tag, m in tags()]
    return {"site": SITE, "edge_id": EDGE_ID, "seq": seq, "sent_at": now.isoformat(), "points": pts}

def main():
    import paho.mqtt.client as mqtt
    host, port = os.getenv("MQTT_ENDPOINT", "localhost:1883").split(":")
    buf = Buffer(os.getenv("BUFFER_DIR", "/tmp/buffer"))
    c = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=EDGE_ID)
    if os.getenv("MQTT_TLS", "false") == "true":
        c.tls_set(ca_certs=os.getenv("MQTT_CA"), certfile=os.getenv("MQTT_CERT"), keyfile=os.getenv("MQTT_KEY"),
                  tls_version=ssl.PROTOCOL_TLS_CLIENT)
    c.reconnect_delay_set(1, 30)
    c.connect_async(host, int(port)); c.loop_start()
    seq = int(time.time())
    anomaly_at = time.time() + float(os.getenv("ANOMALY_AFTER_SECONDS", "120"))
    while True:
        seq += 1
        batch = make_batch(seq, anomaly=time.time() > anomaly_at)
        if c.is_connected():
            for old in buf.drain():
                c.publish(f"petronova/{SITE}/telemetry", json.dumps(old), qos=1)
            info = c.publish(f"petronova/{SITE}/telemetry", json.dumps(batch), qos=1)
            if info.rc != 0:
                buf.put(batch)
        else:
            buf.put(batch)
            print(json.dumps({"severity": "WARNING", "message": "link down, buffered", "pending": len(buf)}), flush=True)
        time.sleep(PERIOD)

if __name__ == "__main__":
    main()
