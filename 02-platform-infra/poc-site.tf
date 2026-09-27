# ---------------------------------------------------------------------------
# POC: simulated plant L3.5 DMZ in its own project/VPC, connected to the hub
# with GCP-to-GCP HA VPN (4 tunnels, BGP). Demonstrates:
#   - only the DMZ prefix is learned by the cloud side
#   - no ingress into the site from cloud (deny-all + logging)
#   - edge simulator publishes MQTT over the tunnel, buffers during link loss
# ---------------------------------------------------------------------------
locals {
  poc = var.poc_site.enabled ? 1 : 0
}

resource "google_compute_network" "site" {
  count                   = local.poc
  project                 = var.project_ids.sim_site
  name                    = "hazira-dmz-sim"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "site" {
  count                    = local.poc
  project                  = var.project_ids.sim_site
  name                     = "dmz"
  region                   = var.regions.primary
  network                  = google_compute_network.site[0].id
  ip_cidr_range            = var.poc_site.dmz_cidr
  private_ip_google_access = true
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 1
  }
}

# Site firewall: nothing may be initiated towards the plant DMZ from cloud.
resource "google_compute_firewall" "site_deny_ingress" {
  count     = local.poc
  project   = var.project_ids.sim_site
  name      = "deny-all-ingress-from-cloud"
  network   = google_compute_network.site[0].id
  direction = "INGRESS"
  priority  = 1000
  deny { protocol = "all" }
  source_ranges = ["0.0.0.0/0"]
  log_config { metadata = "INCLUDE_ALL_METADATA" }
}

resource "google_compute_firewall" "site_iap_ssh" {
  count         = local.poc
  project       = var.project_ids.sim_site
  name          = "allow-iap-ssh-admin"
  network       = google_compute_network.site[0].id
  direction     = "INGRESS"
  priority      = 900
  source_ranges = ["35.235.240.0/20"]
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_ha_vpn_gateway" "site" {
  count   = local.poc
  project = var.project_ids.sim_site
  name    = "site-ha-vpn"
  region  = var.regions.primary
  network = google_compute_network.site[0].id
}

resource "google_compute_ha_vpn_gateway" "hub" {
  count   = local.poc
  project = var.project_ids.net_hub
  name    = "hub-poc-site-ha-vpn"
  region  = var.regions.primary
  network = var.network.hub_network
}

resource "google_compute_router" "site" {
  count   = local.poc
  project = var.project_ids.sim_site
  name    = "site-router"
  region  = var.regions.primary
  network = google_compute_network.site[0].id
  bgp {
    asn               = var.poc_site.site_asn
    advertise_mode    = "CUSTOM"
    advertised_groups = []
    advertised_ip_ranges { range = var.poc_site.dmz_cidr } # ONLY the DMZ, never L0-3
  }
}

resource "google_compute_router" "hub" {
  count   = local.poc
  project = var.project_ids.net_hub
  name    = "hub-poc-site-router"
  region  = var.regions.primary
  network = var.network.hub_network
  bgp {
    asn               = var.poc_site.hub_asn
    advertise_mode    = "CUSTOM"
    advertised_groups = []
    dynamic "advertised_ip_ranges" {
      for_each = var.poc_site.advertise
      content {
        range       = advertised_ip_ranges.key
        description = advertised_ip_ranges.value
      }
    }
  }
}

resource "random_password" "psk" {
  count   = local.poc * 2
  length  = 32
  special = false
}

locals {
  # tunnel index => interface; each side gets two tunnels (one per interface)
  tunnels = var.poc_site.enabled ? { t0 = 0, t1 = 1 } : {}
  bgp_ip = {
    t0 = { hub = "169.254.30.1", site = "169.254.30.2" }
    t1 = { hub = "169.254.30.5", site = "169.254.30.6" }
  }
}

resource "google_compute_vpn_tunnel" "hub_to_site" {
  for_each              = local.tunnels
  project               = var.project_ids.net_hub
  name                  = "hub-to-site-${each.key}"
  region                = var.regions.primary
  vpn_gateway           = google_compute_ha_vpn_gateway.hub[0].id
  vpn_gateway_interface = each.value
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.site[0].id
  shared_secret         = random_password.psk[each.value].result
  router                = google_compute_router.hub[0].id
}

resource "google_compute_vpn_tunnel" "site_to_hub" {
  for_each              = local.tunnels
  project               = var.project_ids.sim_site
  name                  = "site-to-hub-${each.key}"
  region                = var.regions.primary
  vpn_gateway           = google_compute_ha_vpn_gateway.site[0].id
  vpn_gateway_interface = each.value
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.hub[0].id
  shared_secret         = random_password.psk[each.value].result
  router                = google_compute_router.site[0].id
}

resource "google_compute_router_interface" "hub" {
  for_each   = local.tunnels
  project    = var.project_ids.net_hub
  name       = "hub-if-${each.key}"
  region     = var.regions.primary
  router     = google_compute_router.hub[0].name
  ip_range   = "${local.bgp_ip[each.key].hub}/30"
  vpn_tunnel = google_compute_vpn_tunnel.hub_to_site[each.key].name
}

resource "google_compute_router_peer" "hub" {
  for_each                  = local.tunnels
  project                   = var.project_ids.net_hub
  name                      = "hub-peer-${each.key}"
  region                    = var.regions.primary
  router                    = google_compute_router.hub[0].name
  peer_ip_address           = local.bgp_ip[each.key].site
  peer_asn                  = var.poc_site.site_asn
  interface                 = google_compute_router_interface.hub[each.key].name
  advertised_route_priority = 100
}

resource "google_compute_router_interface" "site" {
  for_each   = local.tunnels
  project    = var.project_ids.sim_site
  name       = "site-if-${each.key}"
  region     = var.regions.primary
  router     = google_compute_router.site[0].name
  ip_range   = "${local.bgp_ip[each.key].site}/30"
  vpn_tunnel = google_compute_vpn_tunnel.site_to_hub[each.key].name
}

resource "google_compute_router_peer" "site" {
  for_each        = local.tunnels
  project         = var.project_ids.sim_site
  name            = "site-peer-${each.key}"
  region          = var.regions.primary
  router          = google_compute_router.site[0].name
  peer_ip_address = local.bgp_ip[each.key].hub
  peer_asn        = var.poc_site.hub_asn
  interface       = google_compute_router_interface.site[each.key].name
}

# Edge simulator VM in the DMZ (no public IP). Runs the edge-simulator container.
resource "google_service_account" "edge" {
  count        = local.poc
  project      = var.project_ids.sim_site
  account_id   = "edge-simulator"
  display_name = "POC edge gateway simulator"
}

resource "google_project_iam_member" "edge_ar" {
  count   = local.poc
  project = var.project_ids.artifacts
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.edge[0].email}"
}

resource "google_compute_instance" "edge" {
  count        = var.poc_site.enabled && var.poc_site.edge_image != "" ? 1 : 0
  project      = var.project_ids.sim_site
  name         = "hazira-edge-gw-sim"
  zone         = "${var.regions.primary}-a"
  machine_type = "e2-small"
  tags         = ["edge-gateway"]
  boot_disk {
    initialize_params { image = "cos-cloud/cos-stable" }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.site[0].id
    network_ip = cidrhost(var.poc_site.dmz_cidr, 10)
  }
  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }
  service_account {
    email  = google_service_account.edge[0].email
    scopes = ["cloud-platform"]
  }
  metadata = {
    enable-oslogin = "TRUE"
    gce-container-declaration = yamlencode({
      spec = {
        containers = [{
          image = var.poc_site.edge_image
          env = [
            { name = "MQTT_ENDPOINT", value = var.poc_site.mqtt_endpoint },
            { name = "SITE", value = "hazira" },
            { name = "TAGS", value = "1000" },
            { name = "BUFFER_DIR", value = "/buffer" }
          ]
          volumeMounts = [{ name = "buffer", mountPath = "/buffer" }]
        }]
        volumes       = [{ name = "buffer", hostPath = { path = "/mnt/stateful_partition/buffer" } }]
        restartPolicy = "Always"
      }
    })
  }
}
