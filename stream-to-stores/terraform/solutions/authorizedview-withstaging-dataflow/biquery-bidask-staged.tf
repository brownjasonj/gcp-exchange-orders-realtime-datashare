# 
# file: bigquery-bidask-staged.tf
# description: terraform resource definitions for bigquery table for storing the
# 
resource "google_bigquery_table" "bidask_all_staged" {
  dataset_id          = var.src_dataset_id
  table_id            = "bidask_all_staged"
  project             = var.project_id
  schema              = file("${var.src_bq_schema_file}")
  deletion_protection = false

  # Partitioning by day using the timestamp field
  # https://cloud.google.com/bigquery/docs/partitioned-tables
  # https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/bigquery_table

  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }

  depends_on = [
  ]
}

resource "google_bigquery_table_iam_member" "pubsub_bq_writer_staged" {
  project    = var.project_id
  dataset_id = var.src_dataset_id
  table_id   = google_bigquery_table.bidask_all_staged.table_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_bigquery_table_iam_member" "pubsub_bq_metadata_viewer_staged" {
  project    = var.project_id
  dataset_id = var.src_dataset_id
  table_id   = google_bigquery_table.bidask_all_staged.table_id
  role       = "roles/bigquery.metadataViewer"
  member     = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}
