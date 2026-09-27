"""Streaming telemetry pipeline: Pub/Sub telemetry-raw -> dedupe -> Bigtable (hot) + BigQuery (curated)
+ anomaly events to Pub/Sub telemetry-anomaly. Runs as a Dataflow Flex Template in the data project,
private IPs only, CMEK, in the data subnet of the spoke VPC."""
import argparse, json
import apache_beam as beam
from apache_beam.io.gcp.bigtableio import WriteToBigTable
from apache_beam.options.pipeline_options import PipelineOptions, StandardOptions
from apache_beam.transforms.deduplicate import DeduplicatePerKey
from apache_beam.utils.timestamp import Duration
from google.cloud.bigtable.row import DirectRow
import transforms as T

class ToBigtableRow(beam.DoFn):
    def process(self, d):
        key, cells = T.bigtable_row(d)
        row = DirectRow(row_key=key)
        for col, val in cells.items():
            fam, q = col.split(":")
            row.set_cell(fam, q.encode(), val)
        yield row

def run(argv=None):
    p = argparse.ArgumentParser()
    p.add_argument("--input_subscription", required=True)
    p.add_argument("--anomaly_topic", required=True)
    p.add_argument("--bq_table", required=True)            # project:curated.telemetry
    p.add_argument("--bigtable_project", required=True)
    p.add_argument("--bigtable_instance", required=True)
    args, beam_args = p.parse_known_args(argv)
    opts = PipelineOptions(beam_args, save_main_session=True)
    opts.view_as(StandardOptions).streaming = True
    with beam.Pipeline(options=opts) as pl:
        pts = (pl
               | "Read" >> beam.io.ReadFromPubSub(subscription=args.input_subscription)
               | "Parse" >> beam.Map(T.parse)
               | "Key" >> beam.Map(lambda d: (T.dedupe_key(d), d))
               | "Dedupe" >> DeduplicatePerKey(processing_time_duration=Duration(seconds=72 * 3600))
               | "Values" >> beam.Values())
        (pts | "BTRow" >> beam.ParDo(ToBigtableRow())
             | "ToBigtable" >> WriteToBigTable(project_id=args.bigtable_project, instance_id=args.bigtable_instance, table_id="telemetry"))
        (pts | "BQRow" >> beam.Map(T.bq_row)
             | "ToBigQuery" >> beam.io.WriteToBigQuery(args.bq_table, method="STORAGE_WRITE_API",
                   write_disposition=beam.io.BigQueryDisposition.WRITE_APPEND,
                   create_disposition=beam.io.BigQueryDisposition.CREATE_NEVER))
        (pts | "Detect" >> beam.FlatMap(lambda d: [a for a in [T.anomaly(d)] if a])
             | "Encode" >> beam.Map(lambda a: json.dumps(a).encode())
             | "ToAnomalyTopic" >> beam.io.WriteToPubSub(args.anomaly_topic))

if __name__ == "__main__":
    run()
