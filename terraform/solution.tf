# module "free-pubsub-cloudfunction-bq" {
#   source               = "./solutions/cloudfunction"
#   project_id           = var.project_id
#   region               = var.region
#   delay_in_seconds     = "200"
#   trgt_dataset_id      = google_bigquery_dataset.free_datasets.dataset_id
#   topic_id             = google_pubsub_topic.pricing_topic.name
#   function_bucket_name = google_storage_bucket.function_bucket.name
# }

module "free-bigquery-authorizedview" {
  source           = "./solutions/authorizedview"
  project_id       = var.project_id
  region           = var.region
  delay_in_seconds = 200
  src_dataset_id   = google_bigquery_dataset.paywall_datasets.dataset_id
  src_table_id     = google_bigquery_table.order_ticks_all.table_id
  trgt_dataset_id  = google_bigquery_dataset.free_datasets.dataset_id
}
