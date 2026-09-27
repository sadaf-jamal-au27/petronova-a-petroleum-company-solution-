variable "env" {
  description = "dev or prod."
  type        = string
}
variable "regions" {
  description = "Primary and DR regions."
  type = object({
    primary = optional(string, "asia-south1")
    dr      = optional(string, "asia-south2")
  })
  default = {}
}
variable "dr_enabled" {
  description = "Create DR-region resources (GKE cluster, Bigtable cluster, SQL replica). True for prod."
  type        = bool
  default     = false
}
variable "impersonate_service_account" {
  type    = string
  default = null
}
variable "project_ids" {
  description = "Projects from 2-project-factory."
  type = object({
    apps      = string
    ingest    = string
    data      = string
    ai        = string
    artifacts = string
    net_hub   = string
    sim_site  = optional(string) # POC only: project that simulates a plant DMZ
  })
}
variable "network" {
  description = "From 2-networking outputs."
  type = object({
    spoke_network  = string # self link of the env spoke VPC
    hub_network    = string # self link of hub-0
    gke_subnet     = string
    gke_subnet_dr  = optional(string)
    data_subnet    = string
    master_cidr    = string
    master_cidr_dr = optional(string)
  })
}
variable "kms_keys" {
  description = "CMEK ids from 2-security (primary region; *_dr for asia-south2)."
  type = object({
    gke        = string
    sql        = string
    bigquery   = string
    storage    = string
    pubsub     = string
    storage_dr = optional(string)
    sql_dr     = optional(string)
    gke_dr     = optional(string)
  })
}
variable "gke" {
  type = object({
    authorized_ranges   = optional(map(string), {})
    machine_type        = optional(string, "e2-standard-4")
    spot                = optional(bool, true)
    min_nodes           = optional(number, 1)
    max_nodes           = optional(number, 3)
    deletion_protection = optional(bool, true)
  })
  default = {}
}
variable "bigtable_nodes" {
  type    = number
  default = 1
}
variable "sql_tier" {
  type    = string
  default = "db-custom-1-3840"
}
variable "workload_identities" {
  description = "namespace/ksa => GSA email."
  type        = map(string)
  default     = {}
}
variable "poc_site" {
  description = "POC plant-site simulator connected over HA VPN (GCP to GCP) to the hub."
  type = object({
    enabled       = optional(bool, false)
    dmz_cidr      = optional(string, "172.21.0.0/24")
    site_asn      = optional(number, 65020)
    hub_asn       = optional(number, 64517)
    advertise     = optional(map(string), { "10.130.0.0/20" = "dev spoke", "199.36.153.8/30" = "private googleapis" })
    edge_image    = optional(string, "")
    mqtt_endpoint = optional(string, "mqtt-dev.gcp.petronova.internal:8883")
  })
  default = {}
}
variable "labels" {
  type    = map(string)
  default = { app = "petronova" }
}
