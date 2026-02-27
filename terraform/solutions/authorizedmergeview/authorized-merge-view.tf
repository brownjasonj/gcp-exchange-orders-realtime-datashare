resource "google_bigquery_table" "bidask_all_delayed" {
  dataset_id          = var.trgt_dataset_id
  table_id            = "bidask_all_delayed_authmergeview"
  project             = var.project_id
  deletion_protection = false

  view {
    query          = <<EOF
            SELECT * EXCEPT(row_num)
            FROM (
              SELECT
                *,
                ROW_NUMBER() OVER(PARTITION BY symbol, sequenceNumber ORDER BY ingestion_time DESC) as row_num
              FROM
                `${var.project_id}.${var.src_dataset_id}.${google_bigquery_table.bidask_all_staged.table_id}`
              WHERE
                ingestion_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
                AND CURRENT_TIMESTAMP() > TIMESTAMP_ADD(timestamp, INTERVAL ${var.delay_in_seconds} SECOND)
            )
            WHERE
              row_num = 1
            EOF
    use_legacy_sql = false
  }

  depends_on = [
    google_bigquery_table.bidask_all_staged
  ]
}
