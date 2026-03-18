resource "google_bigquery_table" "bidask_all_final_dedup" {
  dataset_id          = var.trgt_dataset_id
  table_id            = "bidask_all_final_dedup"
  project             = var.project_id
  deletion_protection = false

  view {
    query          = <<EOF
                WITH ranked_events AS (
                    SELECT
                        *,
                        ROW_NUMBER() OVER (
                            PARTITION BY event_id         -- Group duplicates by their unique ID
                            ORDER BY publishTime ASC   -- Keep the earliest arrival
                        ) AS row_num
                    FROM `${var.project_id}.${var.src_dataset_id}.${google_bigquery_table.bidask_all_final.table_id}`
                    WHERE CURRENT_TIMESTAMP() > TIMESTAMP_ADD(timestamp, INTERVAL ${var.delay_in_seconds} SECOND)
                )
                SELECT *
                FROM ranked_events
                WHERE row_num = 1   
            EOF
    use_legacy_sql = false
  }

  depends_on = [
    google_bigquery_table.bidask_all_final
  ]
}

