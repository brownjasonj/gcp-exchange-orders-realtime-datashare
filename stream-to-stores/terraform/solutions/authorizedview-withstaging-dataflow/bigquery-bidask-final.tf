# 
# file: bigquery-bidask-final.tf
# description: terraform resource definitions for bigquery table for storing the
# 
resource "google_bigquery_table" "bidask_all_final" {
  dataset_id          = var.src_dataset_id
  table_id            = "bidask_all_final"
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

resource "google_bigquery_table_iam_member" "pubsub_bq_writer_final" {
  project    = var.project_id
  dataset_id = var.src_dataset_id
  table_id   = google_bigquery_table.bidask_all_final.table_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_bigquery_table_iam_member" "pubsub_bq_metadata_viewer_final" {
  project    = var.project_id
  dataset_id = var.src_dataset_id
  table_id   = google_bigquery_table.bidask_all_final.table_id
  role       = "roles/bigquery.metadataViewer"
  member     = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}



resource "google_bigquery_data_transfer_config" "bidask_merge_scheduler" {
  display_name         = "bidask-merge-scheduler"
  location             = var.region
  data_source_id       = "scheduled_query"
  schedule             = "every 15 minutes"
  project              = var.project_id
  service_account_name = "${data.google_project.project.number}-compute@developer.gserviceaccount.com"

  params = {
    query = <<EOF
MERGE `${var.project_id}.${google_bigquery_table.bidask_all_final.dataset_id}.${google_bigquery_table.bidask_all_final.table_id}` AS T
USING (
  SELECT * EXCEPT(row_num)
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER(PARTITION BY symbol, sequenceNumber ORDER BY ingestion_time DESC) as row_num
    FROM
      `${var.project_id}.${google_bigquery_table.bidask_all_staged.dataset_id}.${google_bigquery_table.bidask_all_staged.table_id}`
    WHERE
      ingestion_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
  )
  WHERE
    row_num = 1
) AS S
ON T.symbol = S.symbol AND T.sequenceNumber = S.sequenceNumber
WHEN NOT MATCHED THEN
  INSERT (symbol, sequenceNumber, price, currency, venue, timestamp, bidAsk, quantity, publishTime, ingestion_time)
  VALUES (symbol, sequenceNumber, price, currency, venue, timestamp, bidAsk, quantity, publishTime, ingestion_time)
EOF
  }

  depends_on = [
    google_bigquery_table.bidask_all_final,
    google_bigquery_table.bidask_all_staged
  ]
}
