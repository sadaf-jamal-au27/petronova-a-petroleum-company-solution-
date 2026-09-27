# petronova-contracts

| File | Contract | Producer -> Consumer |
|---|---|---|
| `events/telemetry-batch.schema.json` | MQTT payload from edge gateways | edge (OT engineering) -> mqtt-bridge, Dataflow |
| `events/alarm.avsc` | Alarm event on Pub/Sub `alarms` | alarm-service -> workorder-service, SecOps |
| `bigquery/curated_telemetry.json` | `curated.telemetry` table | Dataflow -> analysts, Vertex AI |
| `bigquery/alarms.json` | `curated.alarms` table | alarm-service -> reliability engineers |

Tag naming: `<site>.<unit>.<asset_id>.<measurement>` e.g. `hazira.u100.K-101.vib_de_mm_s`.
Asset ids follow ISO 14224 equipment taxonomy. Changes are additive only; PRs need OT engineering + data team review.
