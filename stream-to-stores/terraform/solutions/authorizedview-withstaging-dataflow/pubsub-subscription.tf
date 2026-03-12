# 
# file: pubsub-subscription.tf
# description: pubsub subscription for dataflow job to read from pubsub and write to bigquery
# 
resource "google_pubsub_subscription" "pubsub_bidask_all_to_bq" {
  name  = "pubsub_bidask_all_to_bq"
  topic = var.pubsub_topic_id

  ack_deadline_seconds = 20

  depends_on = [
  ]
}
