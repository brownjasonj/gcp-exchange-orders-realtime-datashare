resource "google_pubsub_subscription" "pricing_to_bq_sub" {
  name  = "pricing-to-bq-sub"
  topic = google_pubsub_topic.pricing_topic.id

  ack_deadline_seconds = 20

  depends_on = [
    google_pubsub_topic.pricing_topic
  ]
}

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
    inputSubscription = google_pubsub_subscription.pricing_to_bq_sub.id
    outputTableSpec   = "${var.project_id}:${google_bigquery_dataset.paywall_datasets.dataset_id}.${google_bigquery_table.order_ticks_all.table_id}"
    tempLocation      = "gs://${google_storage_bucket.dataflow_temp_bucket.name}/temp"
  }

  network    = data.google_compute_network.network.id
  subnetwork = "regions/${var.region}/subnetworks/${data.google_compute_subnetwork.subnetwork.name}"

  depends_on = [
    google_pubsub_subscription.pricing_to_bq_sub,
    google_bigquery_table.order_ticks_all,
    google_storage_bucket.dataflow_temp_bucket,
    data.google_compute_network.network,
    data.google_compute_subnetwork.subnetwork
  ]
}
