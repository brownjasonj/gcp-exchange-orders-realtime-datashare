

module "authorizedview" {
  source             = "./solutions/authorizedview"
  project_id         = var.project_id
  region             = var.region
  delay_in_seconds   = 200
  src_dataset_id     = google_bigquery_dataset.paywall_datasets.dataset_id
  src_bq_schema_file = "${path.module}/../../model/pricing-message-bq-schema.json"
  trgt_dataset_id    = google_bigquery_dataset.free_datasets.dataset_id
  network_id         = var.network_vpc_name
  subnetwork_name    = var.subnetwork_name
}
