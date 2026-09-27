# petronova-data-pipelines

| Path | What |
|---|---|
| `dataflow/` | Streaming Beam pipeline (Flex Template): dedupe replayed points, Bigtable hot store, BigQuery curated, anomaly events |
| `sql/` | Scheduled queries: 1-minute aggregates, compressor features with 7-day failure label |
| `vertex/` | Vertex AI pipeline training a BQML boosted-tree model, registered in Vertex Model Registry |

`dataflow/test_transforms.py` covers parsing, replay de-duplication, anomaly rules and Bigtable key ordering.
