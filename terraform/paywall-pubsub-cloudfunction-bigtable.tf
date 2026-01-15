resource "google_service_account" "bigtable_writer" {
  account_id   = "bigtable-writer-sa"
  display_name = "Bigtable Writer Service Account"
}

resource "google_project_iam_member" "bigtable_writer_user" {
  project = var.project_id
  role    = "roles/bigtable.user"
  member  = "serviceAccount:${google_service_account.bigtable_writer.email}"
}

data "archive_file" "function_source" {
  type        = "zip"
  source_dir  = "${path.module}/cloud-functions/pubsub-to-bigtable"
  output_path = "${path.module}/files/pubsub-to-bigtable.zip"
}

resource "google_storage_bucket_object" "function_archive" {
  name   = "pubsub-to-bigtable-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_bucket.name
  source = data.archive_file.function_source.output_path
}

resource "google_cloudfunctions2_function" "pricing_to_bigtable" {
  name        = "pricing-to-bigtable"
  location    = var.region
  description = "Writes pricing Pub/Sub messages to Bigtable"

  build_config {
    runtime     = "nodejs20"
    entry_point = "processPricing"
    source {
      storage_source {
        bucket = google_storage_bucket.function_bucket.name
        object = google_storage_bucket_object.function_archive.name
      }
    }
  }

  service_config {
    max_instance_count    = 10
    available_memory      = "256M"
    timeout_seconds       = 60
    service_account_email = google_service_account.bigtable_writer.email
    environment_variables = {
      BIGTABLE_INSTANCE_ID = google_bigtable_instance.paywall_instance.name
      BIGTABLE_TABLE_ID    = google_bigtable_table.order_ticks_all.name
    }
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.pricing_topic.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }
}
