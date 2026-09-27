output "clusters" {
  value = { for k, v in module.gke : k => { name = v.name, location = v.location } }
}
output "sql_connection_name" {
  value = module.sql.connection_name
}
output "bigtable_instance" {
  value = google_bigtable_instance.telemetry.name
}
output "poc_vpn_tunnels" {
  value = { for k, t in google_compute_vpn_tunnel.hub_to_site : k => t.name }
}
