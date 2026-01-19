resource "google_bigquery_table" "bt_rt_order_ticks_all" {
  dataset_id          = google_bigquery_dataset.paywall_datasets.dataset_id
  table_id            = "bt_rt_order_ticks_all"
  project             = var.project_id
  deletion_protection = false

  external_data_configuration {
    autodetect    = true
    source_format = "BIGTABLE"
    source_uris = [
      "https://bigtable.googleapis.com/projects/${var.project_id}/instances/${google_bigtable_instance.paywall_instance.name}/tables/${google_bigtable_table.bt_rt_order_ticks_all.name}"
    ]

    bigtable_options {
      read_rowkey_as_string = true
      column_family {
        family_id = "data"
        encoding  = "TEXT"
      }
    }
  }

  depends_on = [
    google_bigtable_table.bt_rt_order_ticks_all
  ]
}
