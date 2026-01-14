resource "google_pubsub_schema" "pricing_schema" {
  name       = "pricing-schema-v1"
  type       = "AVRO"
  definition = file("${path.module}/../model/pricing-message.avsc")
}


resource "google_pubsub_topic" "pricing_topic" {
  name    = var.pubsub_topic
  project = var.project_id
  schema_settings {
    encoding = "JSON"
    schema   = google_pubsub_schema.pricing_schema.id
  }

  depends_on = [
    google_pubsub_schema.pricing_schema
  ]
}
