resource "google_pubsub_subscription" "pricing_to_bq_sub" {
  name  = "pricing-to-bq-sub"
  topic = google_pubsub_topic.pricing_topic.id

  ack_deadline_seconds = 20

  depends_on = [
    google_pubsub_topic.pricing_topic
  ]
}

resource "google_storage_bucket" "dataflow_temp_bucket" {
  name                        = "${var.project_id}-dataflow-temp"
  location                    = var.region
  force_destroy               = true
  uniform_bucket_level_access = true
}

resource "google_dataflow_flex_template_job" "pricing_to_bq_job" {
  provider                = google-beta
  name                    = "pricing-to-bq-job"
  container_spec_gcs_path = "gs://dataflow-templates-${var.region}/latest/flex/PubSub_to_BigQuery_Flex"
  region                  = var.region

  parameters = {
    inputSubscription = google_pubsub_subscription.pricing_to_bq_sub.id
    outputTableSpec   = "${var.project_id}:${google_bigquery_dataset.paywall_datasets.dataset_id}.${google_bigquery_table.df_pricing_order_ticks_all.table_id}"
    tempLocation      = "gs://${google_storage_bucket.dataflow_temp_bucket.name}/temp"
  }

  network    = data.google_compute_network.network.id
  subnetwork = "regions/${var.region}/subnetworks/${data.google_compute_subnetwork.subnetwork.name}"

  depends_on = [
    google_pubsub_subscription.pricing_to_bq_sub,
    google_bigquery_table.df_pricing_order_ticks_all,
    google_storage_bucket.dataflow_temp_bucket,
    data.google_compute_network.network,
    data.google_compute_subnetwork.subnetwork
  ]
}


resource "google_bigquery_table" "df_pricing_order_ticks_all" {
  dataset_id          = google_bigquery_dataset.paywall_datasets.dataset_id
  table_id            = "df_pricing_order_ticks_all"
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
}


resource "google_bigquery_analytics_hub_listing" "pricing_subscription_listing" {
  provider         = google-beta
  project          = var.project_id
  location         = var.region
  data_exchange_id = google_bigquery_analytics_hub_data_exchange.datashare.data_exchange_id
  listing_id       = "pricing_subscription_listing"
  display_name     = "Pricing Subscription Listing"
  description      = "Listing for Pricing Subscription"

  pubsub_topic {
    topic                 = google_pubsub_topic.pricing_topic.id
    data_affinity_regions = [var.region]
  }

  depends_on = [
    google_pubsub_topic.pricing_topic,
    google_bigquery_analytics_hub_data_exchange.datashare
  ]
}
