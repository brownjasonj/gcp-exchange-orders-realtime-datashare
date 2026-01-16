resource "google_bigquery_analytics_hub_data_exchange" "datashare" {
  project          = var.project_id
  location         = var.region
  data_exchange_id = "datashare"
  display_name     = "Datashare Exchange"
  description      = "Analytics Hub Exchange for Datashare"
}
