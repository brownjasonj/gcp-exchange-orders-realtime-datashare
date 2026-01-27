data "google_project" "project" {
  project_id = var.project_id
}

resource "google_bigquery_table_iam_member" "pubsub_bq_writer" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.paywall_datasets.dataset_id
  table_id   = google_bigquery_table.bidask_all_final.table_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_bigquery_table_iam_member" "pubsub_bq_metadata_viewer" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.paywall_datasets.dataset_id
  table_id   = google_bigquery_table.bidask_all_final.table_id
  role       = "roles/bigquery.metadataViewer"
  member     = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_pubsub_subscription" "pubsub_bidask_all_to_bq  _final" {
  name  = "pubsub_bidask_all_to_bq_final"
  topic = google_pubsub_topic.pricing_topic.id

  bigquery_config {
    table               = "${google_bigquery_table.bidask_all_final.project}.${google_bigquery_table.bidask_all_final.dataset_id}.${google_bigquery_table.bidask_all_final.table_id}"
    use_topic_schema    = true
    drop_unknown_fields = true
  }

  depends_on = [
    google_pubsub_topic.pricing_topic,
    google_bigquery_table.bidask_all_final,
    google_bigquery_table_iam_member.pubsub_bq_writer,
    google_bigquery_table_iam_member.pubsub_bq_metadata_viewer
  ]
}
