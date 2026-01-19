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

resource "google_bigquery_analytics_hub_listing" "paywall_datasets_listing" {
  project          = var.project_id
  location         = var.region
  data_exchange_id = google_bigquery_analytics_hub_data_exchange.datashare.data_exchange_id
  listing_id       = "paywall_datasets_listing"
  display_name     = "Paywall Datasets Listing"
  description      = "Listing for Paywall Datasets"

  bigquery_dataset {
    dataset = google_bigquery_dataset.paywall_datasets.id
  }

  depends_on = [
    google_bigquery_analytics_hub_data_exchange.datashare
  ]
}
