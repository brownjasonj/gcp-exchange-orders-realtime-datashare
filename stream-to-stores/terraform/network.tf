data "google_compute_network" "network" {
  project = var.project_id
  name    = var.network_vpc_name
}

data "google_compute_subnetwork" "subnetwork" {
  project = var.project_id
  name    = var.subnetwork_name
  region  = var.region
}
