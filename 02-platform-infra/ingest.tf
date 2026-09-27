# Telemetry backbone. Message storage restricted to Indian regions (residency).
locals {
  topics = {
    telemetry-raw     = { retention = "604800s" } # 7 days replay window
    telemetry-anomaly = { retention = "86400s" }
    alarms            = { retention = "604800s" }
    workorder-drafts  = { retention = "604800s" }
  }
  df_sa = "dataflow-worker@${var.project_ids.data}.iam.gserviceaccount.com"
  subscriptions = {
    telemetry-raw     = { "telemetry-raw-dataflow" = local.df_sa }
    telemetry-anomaly = { "telemetry-anomaly-alarm-service" = "alarm-service@${var.project_ids.apps}.iam.gserviceaccount.com" }
    alarms            = { "alarms-workorder-service" = "workorder-service@${var.project_ids.apps}.iam.gserviceaccount.com" }
    workorder-drafts  = {}
  }
}

module "dlq" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/pubsub?ref=v58.0.0"
  project_id = var.project_ids.ingest
  name       = "petronova-dead-letter"
  kms_key    = var.kms_keys.pubsub
  regions    = [var.regions.primary, var.regions.dr]
  labels     = var.labels
}

module "topics" {
  source                     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/pubsub?ref=v58.0.0"
  for_each                   = local.topics
  project_id                 = var.project_ids.ingest
  name                       = each.key
  kms_key                    = var.kms_keys.pubsub
  regions                    = [var.regions.primary, var.regions.dr]
  message_retention_duration = each.value.retention
  labels                     = var.labels
  subscriptions = {
    for sub, sa in local.subscriptions[each.key] : sub => {
      ack_deadline_seconds    = 60
      enable_message_ordering = each.key == "telemetry-raw"
      dead_letter_policy      = { topic = module.dlq.id, max_delivery_attempts = 10 }
      iam                     = { "roles/pubsub.subscriber" = ["serviceAccount:${sa}"] }
    }
  }
}

resource "google_pubsub_topic_iam_member" "publishers" {
  for_each = {
    telemetry-raw     = "mqtt-bridge@${var.project_ids.apps}.iam.gserviceaccount.com"
    telemetry-anomaly = local.df_sa
    alarms            = "alarm-service@${var.project_ids.apps}.iam.gserviceaccount.com"
    workorder-drafts  = "workorder-service@${var.project_ids.apps}.iam.gserviceaccount.com"
  }
  project = var.project_ids.ingest
  topic   = module.topics[each.key].id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${each.value}"
}
