# Zip the cloud function source
data "archive_file" "function_source" {
  type        = "zip"
  source_dir  = "${path.module}/cloud-functions/process-pricing"
  output_path = "${path.module}/files/process-pricing.zip"
}

# Upload the zip to the bucket
resource "google_storage_bucket_object" "function_source_zip" {
  name   = "process-pricing-${data.archive_file.function_source.output_md5}.zip"
  bucket = var.function_bucket_name
  source = data.archive_file.function_source.output_path
}

# Service Account for the Function Identity
resource "google_service_account" "pricing_function_sa" {
  account_id   = "pricing-func-sa"
  display_name = "Pricing Function Service Account"
}

# Grant permissions to the Function SA
# 1. BigQuery Data Editor
resource "google_bigquery_dataset_iam_member" "dataset_editor" {
  dataset_id = var.trgt_dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.pricing_function_sa.email}"
}

# Cloud Function (Gen 2)
resource "google_cloudfunctions2_function" "process_pricing" {
  name        = "process-pricing-message"
  location    = var.region
  description = "Processes pricing messages with delay"

  build_config {
    runtime     = "nodejs20"
    entry_point = "processPricingMessage"
    source {
      storage_source {
        bucket = var.function_bucket_name
        object = google_storage_bucket_object.function_source_zip.name
      }
    }
  }

  service_config {
    max_instance_count = 100
    available_memory   = "256M"
    timeout_seconds    = 60

    environment_variables = {
      PROJECT_ID       = var.project_id
      DATASET_ID       = var.trgt_dataset_id
      TABLE_ID         = google_bigquery_table.order_ticks_delay.table_id
      DELAY_IN_SECONDS = var.delay_in_seconds
    }

    service_account_email = google_service_account.pricing_function_sa.email
  }
}

# Service Account for Pub/Sub Subscription Identity (to invoke the function)
resource "google_service_account" "subscription_invoker_sa" {
  account_id   = "pricing-sub-invoker"
  display_name = "Pricing Subscription Invoker"
}

# Grant Invoker permission to the Subscription SA on the Cloud Run service
resource "google_cloud_run_service_iam_member" "invoker_binding" {
  location = google_cloudfunctions2_function.process_pricing.location
  project  = google_cloudfunctions2_function.process_pricing.project
  service  = google_cloudfunctions2_function.process_pricing.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.subscription_invoker_sa.email}"
}

# Pub/Sub Subscription
resource "google_pubsub_subscription" "free_pricing_subscription" {
  name  = "free_pricing_subscription"
  topic = var.topic_id

  ack_deadline_seconds = 600 # 10 minutes, plenty of time since we Nack early if needed

  push_config {
    push_endpoint = google_cloudfunctions2_function.process_pricing.service_config[0].uri

    oidc_token {
      service_account_email = google_service_account.subscription_invoker_sa.email
    }
  }

  # Retry policy (optional, but good for Nack usage)
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  depends_on = [
    google_cloud_run_service_iam_member.invoker_binding
  ]
}
