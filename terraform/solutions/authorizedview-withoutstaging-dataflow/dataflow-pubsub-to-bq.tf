resource "google_storage_bucket" "dataflow_temp_bucket" {
  name                        = "${var.project_id}-dataflow-temp"
  location                    = var.region
  force_destroy               = true
  uniform_bucket_level_access = true
}

resource "google_dataflow_flex_template_job" "pricing_to_bq_job" {
  provider                = google-beta
  name                    = "pricing-to-bq-job"
  container_spec_gcs_path = "gs://dataflow-templates-${var.region}/latest/flex/PubSub_to_BigQuery_Flex"
  region                  = var.region

  parameters = {
    inputSubscription = google_pubsub_subscription.pubsub_bidask_all_to_bq.id
    outputTableSpec   = "${var.project_id}:${google_bigquery_table.bidask_all_final.dataset_id}.${google_bigquery_table.bidask_all_final.table_id}"
    tempLocation      = "gs://${google_storage_bucket.dataflow_temp_bucket.name}/temp"
    maxNumWorkers     = "999"
    workerMachineType = "n2-standard-8"
  }

  network                 = var.network_id
  subnetwork              = "regions/${var.region}/subnetworks/${var.subnetwork_name}"
  enable_streaming_engine = true

  depends_on = [
    google_pubsub_subscription.pubsub_bidask_all_to_bq,
    google_bigquery_table.bidask_all_final,
    google_storage_bucket.dataflow_temp_bucket
  ]
}
