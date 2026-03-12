resource "google_bigquery_table" "bidask_all_delayed" {
  dataset_id          = var.trgt_dataset_id
  table_id            = "bidask_all_delayed_authview"
  project             = var.project_id
  deletion_protection = false

  view {
    query          = <<EOF
            SELECT * FROM `${var.project_id}.${var.src_dataset_id}.${google_bigquery_table.bidask_all_final.table_id}` 
            WHERE CURRENT_TIMESTAMP() > TIMESTAMP_ADD(timestamp, INTERVAL ${var.delay_in_seconds} SECOND)
            EOF
    use_legacy_sql = false
  }

  depends_on = [
    google_bigquery_table.bidask_all_final
  ]
}
