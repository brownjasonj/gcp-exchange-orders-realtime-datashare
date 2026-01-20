# 
# file: paywall-pubsub-bigquery.tf
# description: terraform resource definitions for paywall pubsub to bigquery subscription and bigquery table 
# 

resource "google_bigquery_table" "pubsub_pricing_order_ticks_all" {
  dataset_id          = google_bigquery_dataset.paywall_datasets.dataset_id
  table_id            = "pubsub_pricing_order_ticks_all"
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

  depends_on = [
    google_bigquery_dataset.paywall_datasets
  ]
}

data "google_project" "project" {
  project_id = var.project_id
}

resource "google_bigquery_table_iam_member" "pubsub_bq_writer" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.paywall_datasets.dataset_id
  table_id   = google_bigquery_table.pubsub_pricing_order_ticks_all.table_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_bigquery_table_iam_member" "pubsub_bq_metadata_viewer" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.paywall_datasets.dataset_id
  table_id   = google_bigquery_table.pubsub_pricing_order_ticks_all.table_id
  role       = "roles/bigquery.metadataViewer"
  member     = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_pubsub_subscription" "pubsub_pricing_order_ticks_all_to_bq" {
  name  = "pubsub_pricing_order_ticks_all_to_bq"
  topic = google_pubsub_topic.pricing_topic.id

  bigquery_config {
    table               = "${google_bigquery_table.pubsub_pricing_order_ticks_all.project}.${google_bigquery_table.pubsub_pricing_order_ticks_all.dataset_id}.${google_bigquery_table.pubsub_pricing_order_ticks_all.table_id}"
    use_topic_schema    = true
    drop_unknown_fields = true
  }

  depends_on = [
    google_pubsub_topic.pricing_topic,
    google_bigquery_table.pubsub_pricing_order_ticks_all,
    google_bigquery_table_iam_member.pubsub_bq_writer,
    google_bigquery_table_iam_member.pubsub_bq_metadata_viewer
  ]
}
