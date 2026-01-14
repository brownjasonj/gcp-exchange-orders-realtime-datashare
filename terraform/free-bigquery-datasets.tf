resource "google_bigquery_dataset" "free_datasets" {
  dataset_id    = "free_datasets"
  friendly_name = "free-datasets"
  description   = "Dataset for free data"
  location      = var.region
  project       = var.project_id
}

resource "google_bigquery_table" "order_ticks_delay" {
  dataset_id          = google_bigquery_dataset.free_datasets.dataset_id
  table_id            = "order_ticks_delay"
  project             = var.project_id
  schema              = file("${path.module}/../model/pricing-message-bq-schema.json")
  deletion_protection = false

  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }
}
