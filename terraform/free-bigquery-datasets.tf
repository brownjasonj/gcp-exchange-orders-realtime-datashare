resource "google_bigquery_dataset" "free_datasets" {
  dataset_id    = "free_datasets"
  friendly_name = "free-datasets"
  description   = "Dataset for free data"
  location      = var.region
  project       = var.project_id
}
