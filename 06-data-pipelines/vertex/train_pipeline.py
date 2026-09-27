"""Vertex AI pipeline (KFP v2): BigQuery features -> BigQuery ML boosted tree -> evaluate -> register if better.
Kept in BQML to stay inside the VPC-SC perimeter with no custom training images for the POC."""
from kfp import dsl, compiler
from google_cloud_pipeline_components.v1.bigquery import BigqueryCreateModelJobOp, BigqueryEvaluateModelJobOp

@dsl.pipeline(name="compressor-failure-7d")
def pipeline(project: str, location: str = "asia-south1", dataset: str = "features"):
    train = BigqueryCreateModelJobOp(
        project=project, location=location,
        query=f"""CREATE OR REPLACE MODEL `{project}.{dataset}.compressor_fail_7d`
                  OPTIONS(model_type='BOOSTED_TREE_CLASSIFIER', input_label_cols=['label_fail_7d'],
                          auto_class_weights=TRUE, data_split_method='SEQ', data_split_col='day',
                          model_registry='VERTEX_AI', vertex_ai_model_id='compressor-fail-7d') AS
                  SELECT * EXCEPT(asset_id) FROM `{project}.{dataset}.compressor_daily`""")
    BigqueryEvaluateModelJobOp(project=project, location=location, model=train.outputs["model"])

if __name__ == "__main__":
    compiler.Compiler().compile(pipeline, "compressor_failure_7d.json")
