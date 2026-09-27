# Hybrid connectivity and pipeline health alerts. Metrics: Cloud Router, VPN, Interconnect, Pub/Sub, Dataflow, app PromQL.
terraform {
  required_version = ">= 1.9.0"
  required_providers {
    google = { source = "hashicorp/google", version = ">= 7.40.0, < 8.0.0" }
  }
  backend "gcs" {}
}

variable "project_id" {
  description = "Scoping project for metrics (hub or monitoring project with metrics scope over spokes)."
  type        = string
}

variable "notification_email" {
  type    = string
  default = "noc@petronova-lab.in"
}

resource "google_monitoring_notification_channel" "noc" {
  project      = var.project_id
  display_name = "petronova-noc"
  type         = "email"
  labels       = { email_address = var.notification_email }
}

locals {
  mql_alerts = {
    bgp_session_down = {
      name     = "Hybrid: BGP session down"
      severity = "CRITICAL"
      filter   = "resource.type = \"gce_router\" AND metric.type = \"router.googleapis.com/bgp/session_up\""
      reducer  = "REDUCE_MIN"
      compare  = "COMPARISON_LT"
      value    = 1
      duration = "60s"
    }
    vpn_tunnel_down = {
      name     = "Hybrid: VPN tunnel not established"
      severity = "ERROR"
      filter   = "resource.type = \"vpn_gateway\" AND metric.type = \"vpn.googleapis.com/tunnel_established\""
      reducer  = "REDUCE_MIN"
      compare  = "COMPARISON_LT"
      value    = 1
      duration = "120s"
    }
    interconnect_capacity = {
      name     = "Hybrid: Interconnect attachment > 70% capacity"
      severity = "WARNING"
      filter   = "resource.type = \"interconnect_attachment\" AND metric.type = \"interconnect.googleapis.com/network/attachment/capacity\""
      reducer  = "REDUCE_MAX"
      compare  = "COMPARISON_GT"
      value    = 0.7
      duration = "900s"
    }
    ingest_backlog = {
      name     = "Ingest: telemetry-raw oldest unacked > 120 s"
      severity = "ERROR"
      filter   = "resource.type = \"pubsub_subscription\" AND resource.label.subscription_id = \"telemetry-raw-dataflow\" AND metric.type = \"pubsub.googleapis.com/subscription/oldest_unacked_message_age\""
      reducer  = "REDUCE_MAX"
      compare  = "COMPARISON_GT"
      value    = 120
      duration = "300s"
    }
    dataflow_lag = {
      name     = "Pipeline: Dataflow system lag > 60 s"
      severity = "ERROR"
      filter   = "resource.type = \"dataflow_job\" AND metric.type = \"dataflow.googleapis.com/job/system_lag\""
      reducer  = "REDUCE_MAX"
      compare  = "COMPARISON_GT"
      value    = 60
      duration = "300s"
    }
  }
}

resource "google_monitoring_alert_policy" "infra" {
  for_each     = local.mql_alerts
  project      = var.project_id
  display_name = each.value.name
  combiner     = "OR"
  severity     = each.value.severity
  conditions {
    display_name = each.value.name
    condition_threshold {
      filter          = each.value.filter
      comparison      = each.value.compare
      threshold_value = each.value.value
      duration        = each.value.duration
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = each.value.reducer == "REDUCE_MIN" ? "ALIGN_MIN" : "ALIGN_MAX"
        cross_series_reducer = each.value.reducer
        group_by_fields      = ["resource.label.project_id"]
      }
    }
  }
  notification_channels = [google_monitoring_notification_channel.noc.id]
  documentation {
    content   = "Runbook: docs/RUNBOOKS.md (hybrid and ingest sections)."
    mime_type = "text/markdown"
  }
}

resource "google_monitoring_alert_policy" "bridge_rejects" {
  project      = var.project_id
  display_name = "Ingest: edge batches rejected by mqtt-bridge"
  combiner     = "OR"
  severity     = "WARNING"
  conditions {
    display_name = "rejected > 1/min for 10m"
    condition_prometheus_query_language {
      query               = "sum by (site) (rate(petronova_bridge_batches_total{result=\"rejected\"}[5m])) * 60 > 1"
      duration            = "600s"
      evaluation_interval = "60s"
    }
  }
  notification_channels = [google_monitoring_notification_channel.noc.id]
}

resource "google_monitoring_alert_policy" "site_silent" {
  project      = var.project_id
  display_name = "Ingest: a site stopped sending (link or edge failure)"
  combiner     = "OR"
  severity     = "ERROR"
  conditions {
    display_name = "no batches from a site for 5m"
    condition_prometheus_query_language {
      query               = "sum by (site) (rate(petronova_bridge_batches_total{result=\"ok\"}[5m])) == 0"
      duration            = "300s"
      evaluation_interval = "60s"
    }
  }
  notification_channels = [google_monitoring_notification_channel.noc.id]
}
