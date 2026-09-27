# Stage 3 - PetroNova workloads (Platform + Data teams). Fabric modules pinned to v58.0.0.
terraform {
  required_version = ">= 1.9.0"
  required_providers {
    google      = { source = "hashicorp/google", version = ">= 7.40.0, < 8.0.0" }
    google-beta = { source = "hashicorp/google-beta", version = ">= 7.40.0, < 8.0.0" }
  }
  backend "gcs" {}
}
provider "google" { impersonate_service_account = var.impersonate_service_account }
provider "google-beta" { impersonate_service_account = var.impersonate_service_account }
