# 
# file: paywall-bigquery-datasets.tf
# description: terraform resource definitions for paywall
#               bigquery datasets and analytics hub listing of the dataset
# 

resource "google_bigquery_dataset" "paywall_datasets" {
  dataset_id    = "paywall_datasets"
  friendly_name = "paywall-datasets"
  description   = "Dataset for paywall data"
  location      = var.region
  project       = var.project_id
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
