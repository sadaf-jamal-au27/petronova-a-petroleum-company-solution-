locals {
  node_sa = "gke-nodes@${var.project_ids.apps}.iam.gserviceaccount.com"
  clusters = merge(
    { primary = { region = var.regions.primary, subnet = var.network.gke_subnet, master = var.network.master_cidr, key = var.kms_keys.gke } },
    var.dr_enabled ? { dr = { region = var.regions.dr, subnet = var.network.gke_subnet_dr, master = var.network.master_cidr_dr, key = var.kms_keys.gke_dr } } : {}
  )
}

module "gke" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/gke-cluster-standard?ref=v58.0.0"
  for_each   = local.clusters
  project_id = var.project_ids.apps
  name       = "petronova-${var.env}-${each.key}"
  location   = each.value.region # regional clusters
  labels     = merge(var.labels, { environment = var.env, role = each.key })
  vpc_config = {
    network               = var.network.spoke_network
    subnetwork            = each.value.subnet
    secondary_range_names = { pods = "pods", services = "services" }
  }
  access_config = {
    ip_access = {
      authorized_ranges       = var.gke.authorized_ranges
      disable_public_endpoint = var.env == "prod"
    }
    master_ipv4_cidr_block = each.value.master
    private_nodes          = true
  }
  release_channel = var.env == "prod" ? "STABLE" : "REGULAR"
  node_config = {
    service_account               = local.node_sa
    workload_metadata_config_mode = "GKE_METADATA"
  }
  enable_features = {
    dataplane_v2            = true
    gateway_api             = true
    workload_identity       = true
    shielded_nodes          = true
    binary_authorization    = true
    database_encryption     = { state = "ENCRYPTED", key_name = each.value.key }
    security_posture_config = { mode = "ENTERPRISE", vulnerability_mode = "VULNERABILITY_ENTERPRISE" }
  }
  monitoring_config = {
    enable_managed_prometheus = true
    enable_deployment_metrics = true
    enable_pod_metrics        = true
  }
  deletion_protection = var.gke.deletion_protection
}

module "nodepool" {
  source          = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/gke-nodepool?ref=v58.0.0"
  for_each        = local.clusters
  project_id      = var.project_ids.apps
  cluster_name    = module.gke[each.key].name
  location        = each.value.region
  name            = "apps"
  service_account = { email = local.node_sa }
  node_config = {
    machine_type             = var.gke.machine_type
    spot                     = var.gke.spot
    shielded_instance_config = { enable_integrity_monitoring = true, enable_secure_boot = true }
  }
  nodepool_config = {
    autoscaling = {
      min_node_count = each.key == "dr" ? 0 : var.gke.min_nodes # DR is warm standby: scaled up on failover
      max_node_count = var.gke.max_nodes
    }
    management = { auto_repair = true, auto_upgrade = true }
  }
}

resource "google_service_account_iam_member" "workload_identity" {
  for_each           = var.workload_identities
  service_account_id = "projects/${regex("@([^.]+)\\.iam", each.value)[0]}/serviceAccounts/${each.value}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_ids.apps}.svc.id.goog[${each.key}]"
  depends_on         = [module.gke]
}

resource "google_project_iam_member" "nodes_ar_reader" {
  project = var.project_ids.artifacts
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${local.node_sa}"
}
