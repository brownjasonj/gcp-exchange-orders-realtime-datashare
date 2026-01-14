resource "google_bigquery_dataset" "paywall_datasets" {
  dataset_id    = "paywall_datasets"
  friendly_name = "paywall-datasets"
  description   = "Dataset for paywall data"
  location      = var.region
  project       = var.project_id
}

resource "google_bigquery_table" "order_ticks_all" {
  dataset_id          = google_bigquery_dataset.paywall_datasets.dataset_id
  table_id            = "order_ticks_all"
  project             = var.project_id
  schema              = file("${path.module}/../model/pricing-message-bq-schema.json")
  deletion_protection = false

  # Partitioning by day using the timestamp field
  # https://cloud.google.com/bigquery/docs/partitioned-tables
  # https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/bigquery_table

  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }
}
