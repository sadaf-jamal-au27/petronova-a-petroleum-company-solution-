# ---------------- Bigtable: hot time series (multi-cluster in prod for DR) ----------------
resource "google_bigtable_instance" "telemetry" {
  project             = var.project_ids.data
  name                = "pn-telemetry-${var.env}"
  deletion_protection = var.env == "prod"
  labels              = merge(var.labels, { environment = var.env })
  cluster {
    cluster_id   = "pn-${var.env}-as1"
    zone         = "${var.regions.primary}-a"
    num_nodes    = var.bigtable_nodes
    storage_type = "SSD"
    kms_key_name = var.kms_keys.storage
  }
  dynamic "cluster" {
    for_each = var.dr_enabled ? [1] : []
    content {
      cluster_id   = "pn-${var.env}-as2"
      zone         = "${var.regions.dr}-a"
      num_nodes    = var.bigtable_nodes
      storage_type = "SSD"
      kms_key_name = var.kms_keys.storage_dr
    }
  }
}

resource "google_bigtable_table" "telemetry" {
  project       = var.project_ids.data
  instance_name = google_bigtable_instance.telemetry.name
  name          = "telemetry"
  # row key: <asset_id>#<tag>#<reverse_ts>
  column_family { family = "m" } # measurements
  column_family { family = "q" } # quality flags
}

resource "google_bigtable_gc_policy" "hot_90d" {
  project         = var.project_ids.data
  instance_name   = google_bigtable_instance.telemetry.name
  table           = google_bigtable_table.telemetry.name
  column_family   = "m"
  deletion_policy = "ABANDON"
  max_age { duration = "2160h" }
}

resource "google_bigtable_app_profile" "serving" {
  project                       = var.project_ids.data
  instance                      = google_bigtable_instance.telemetry.name
  app_profile_id                = "serving"
  multi_cluster_routing_use_any = true
  ignore_warnings               = true
}

resource "google_bigtable_instance_iam_member" "readers" {
  project  = var.project_ids.data
  instance = google_bigtable_instance.telemetry.name
  role     = "roles/bigtable.reader"
  member   = "serviceAccount:timeseries-api@${var.project_ids.apps}.iam.gserviceaccount.com"
}

# ---------------- BigQuery lakehouse ----------------
resource "google_bigquery_dataset" "layers" {
  for_each   = toset(["raw", "curated", "features", "marts", "audit"])
  project    = var.project_ids.data
  dataset_id = each.key
  location   = var.regions.primary
  labels     = merge(var.labels, { environment = var.env, layer = each.key })
  default_encryption_configuration { kms_key_name = var.kms_keys.bigquery }
}

resource "google_bigquery_table" "telemetry_curated" {
  project             = var.project_ids.data
  dataset_id          = google_bigquery_dataset.layers["curated"].dataset_id
  table_id            = "telemetry"
  deletion_protection = var.env == "prod"
  time_partitioning {
    type  = "DAY"
    field = "ts"
  }
  clustering = ["site", "asset_id", "tag"]
  schema     = file("${path.module}/../04-contracts/bigquery/curated_telemetry.json")
}

resource "google_bigquery_table" "alarms" {
  project             = var.project_ids.data
  dataset_id          = google_bigquery_dataset.layers["curated"].dataset_id
  table_id            = "alarms"
  deletion_protection = var.env == "prod"
  time_partitioning {
    type  = "DAY"
    field = "raised_at"
  }
  schema = file("${path.module}/../04-contracts/bigquery/alarms.json")
}

# ---------------- GCS: dual-region raw archive with turbo replication ----------------
resource "google_storage_bucket" "archive" {
  project                     = var.project_ids.data
  name                        = "${var.project_ids.data}-telemetry-archive"
  location                    = "ASIA"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  rpo                         = var.dr_enabled ? "ASYNC_TURBO" : null
  custom_placement_config {
    data_locations = [upper(var.regions.primary), upper(var.regions.dr)]
  }
  autoclass { enabled = true }
  encryption { default_kms_key_name = var.kms_keys.storage }
  labels = merge(var.labels, { environment = var.env })
}

resource "google_storage_bucket" "dataflow" {
  project                     = var.project_ids.data
  name                        = "${var.project_ids.data}-dataflow"
  location                    = upper(var.regions.primary)
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  encryption { default_kms_key_name = var.kms_keys.storage }
  lifecycle_rule {
    action { type = "Delete" }
    condition { age = 30 }
  }
}
