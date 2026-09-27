# Cloud SQL for app state (asset registry, alarms, work orders). Cross-region replica in prod for Tier-2 DR.
module "sql" {
  source                        = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/cloudsql-instance?ref=v58.0.0"
  project_id                    = var.project_ids.apps
  name                          = "pn-apps-${var.env}"
  region                        = var.regions.primary
  database_version              = "POSTGRES_16"
  tier                          = var.sql_tier
  edition                       = var.env == "prod" ? "ENTERPRISE_PLUS" : "ENTERPRISE"
  availability_type             = var.env == "prod" ? "REGIONAL" : "ZONAL"
  encryption_key_name           = var.kms_keys.sql
  gcp_deletion_protection       = var.env == "prod"
  terraform_deletion_protection = var.env == "prod"
  labels                        = merge(var.labels, { environment = var.env })
  databases                     = ["assets", "alarms", "workorders"]
  network_config = {
    connectivity = { psa_config = { private_network = var.network.spoke_network } }
  }
  flags = { "cloudsql.iam_authentication" = "on" }
  backup_configuration = {
    enabled                        = true
    point_in_time_recovery_enabled = true
    retention_count                = var.env == "prod" ? 30 : 7
    location                       = var.regions.primary
  }
  replicas = var.dr_enabled ? {
    dr = { region = var.regions.dr, encryption_key_name = var.kms_keys.sql_dr }
  } : {}
  users = {
    for s in ["alarm-service", "asset-registry", "workorder-service"] :
    "${s}@${var.project_ids.apps}.iam" => { type = "CLOUD_IAM_SERVICE_ACCOUNT" }
  }
}
