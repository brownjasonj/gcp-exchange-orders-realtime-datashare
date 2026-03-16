
# module "authorizedview-withoutstaging-dataflow" {
#   source             = "./solutions/authorizedview-withoutstaging-dataflow"
#   project_id         = var.project_id
#   region             = var.region
#   network_id         = var.network_vpc_name
#   subnetwork_name    = var.subnetwork_name
#   delay_in_seconds   = 200
#   src_dataset_id     = google_bigquery_dataset.paywall_datasets.dataset_id
#   src_bq_schema_file = "${path.module}/../model/pricing-message-bq-schema.json"
#   retention_days     = 2
#   trgt_dataset_id    = google_bigquery_dataset.free_datasets.dataset_id
#   pubsub_topic_id    = google_pubsub_topic.pricing_topic.id
# }


module "authorizedview-withstaging-dataflow" {
  source                = "./solutions/authorizedview-withstaging-dataflow"
  project_id            = var.project_id
  region                = var.region
  delay_in_seconds      = 200
  src_dataset_id        = google_bigquery_dataset.paywall_datasets.dataset_id
  src_bq_schema_file    = "${path.module}/../../model/pricing-message-bq-schema.json"
  staged_retention_days = 1
  final_retention_days  = 2
  trgt_dataset_id       = google_bigquery_dataset.free_datasets.dataset_id
  pubsub_topic_id       = google_pubsub_topic.pricing_topic.id
  network_id            = var.network_vpc_name
  subnetwork_name       = var.subnetwork_name
}
