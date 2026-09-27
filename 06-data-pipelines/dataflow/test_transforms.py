import json
import transforms as T

PT = {"site": "hazira", "edge_id": "e1", "seq": 1, "asset_id": "K-101", "tag": "hazira.u100.K-101.vib_de_mm_s",
      "ts": "2026-09-23T10:00:00+00:00", "value": 8.4, "unit": "mm/s", "quality": "GOOD"}

def test_parse_and_dedupe_key_stable_across_replay():
    a = T.parse(json.dumps(PT).encode()); b = T.parse(json.dumps({**PT, "replayed": True, "seq": 99}).encode())
    assert T.dedupe_key(a) == T.dedupe_key(b)

def test_anomaly_rules():
    d = T.parse(json.dumps(PT).encode())
    a = T.anomaly(d)
    assert a and a["rule"] == "vib_de_mm_s_hi" and a["threshold"] == 7.1
    assert T.anomaly({**d, "value": 3.0}) is None
    assert T.anomaly({**d, "quality": "BAD"}) is None

def test_bigtable_row_newest_first():
    d = T.parse(json.dumps(PT).encode()); later = {**d, "ts_ms": d["ts_ms"] + 1000}
    assert T.bigtable_row(later)[0] < T.bigtable_row(d)[0]
