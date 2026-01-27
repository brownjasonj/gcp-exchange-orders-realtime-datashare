resource "google_bigquery_dataset" "free_datasets" {
  dataset_id    = "free_datasets"
  friendly_name = "free-datasets"
  description   = "Dataset for free data"
  location      = var.region
  project       = var.project_id
}

resource "google_bigquery_analytics_hub_listing" "free_datasets_listing" {
  project          = var.project_id
  location         = var.region
  data_exchange_id = google_bigquery_analytics_hub_data_exchange.datashare.data_exchange_id
  listing_id       = "free_datasets_listing"
  display_name     = "Free Datasets Listing"
  description      = "Listing for Free Datasets"

  bigquery_dataset {
    dataset = google_bigquery_dataset.free_datasets.id
  }

  depends_on = [
    google_bigquery_analytics_hub_data_exchange.datashare
  ]
}

resource "google_bigquery_analytics_hub_listing_iam_member" "public_access" {
  project          = var.project_id
  location         = var.region
  data_exchange_id = google_bigquery_analytics_hub_data_exchange.datashare.data_exchange_id
  listing_id       = google_bigquery_analytics_hub_listing.free_datasets_listing.listing_id
  role             = "roles/analyticshub.subscriber"
  member           = "allAuthenticatedUsers"
}
