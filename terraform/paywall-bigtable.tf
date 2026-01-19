resource "google_bigtable_instance" "paywall_instance" {
  name                = "paywall-instance"
  project             = var.project_id
  deletion_protection = false

  cluster {
    cluster_id   = "paywall-cluster"
    zone         = "${var.region}-a"
    num_nodes    = 1
    storage_type = "SSD"
  }
}

resource "google_bigtable_table" "bt_rt_order_ticks_all" {
  name          = "bt_rt_order_ticks_all"
  instance_name = google_bigtable_instance.paywall_instance.name
  project       = var.project_id

  column_family {
    family = "data"
  }

  depends_on = [google_bigquery_table.pubsub_pricing_order_ticks_all,
  ]
}

resource "google_bigtable_gc_policy" "bt_rt_order_ticks_all_gc" {
  instance_name = google_bigtable_instance.paywall_instance.name
  table         = google_bigtable_table.bt_rt_order_ticks_all.name
  column_family = "data"
  max_age {
    duration = "48h"
  }

  depends_on = [google_bigtable_table.bt_rt_order_ticks_all]
}
