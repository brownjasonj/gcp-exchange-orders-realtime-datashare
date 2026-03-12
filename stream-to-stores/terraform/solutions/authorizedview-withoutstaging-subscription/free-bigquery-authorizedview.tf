resource "google_bigquery_table" "order_ticks_delay" {
  dataset_id          = var.trgt_dataset_id
  table_id            = "order_ticks_delay_authview"
  project             = var.project_id
  deletion_protection = false

  view {
    query          = <<EOF
            SELECT * FROM `${var.project_id}.${var.src_dataset_id}.${google_bigquery_table.bidask_all.table_id}` 
            WHERE CURRENT_TIMESTAMP() > TIMESTAMP_ADD(timestamp, INTERVAL ${var.delay_in_seconds} SECOND)
            EOF
    use_legacy_sql = false
  }

  depends_on = [
    google_bigquery_table.bidask_all
  ]
}
