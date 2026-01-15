
resource "google_bigquery_table" "order_ticks_delay" {
  dataset_id          = var.trgt_dataset_id
  table_id            = "order_ticks_delay"
  project             = var.project_id
  schema              = file("${path.module}/../../../model/pricing-message-bq-schema.json")
  deletion_protection = false

  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }
}
