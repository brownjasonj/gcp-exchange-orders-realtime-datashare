resource "google_pubsub_subscription" "pubsub_bidask_all_to_bq" {
  name  = "pubsub_bidask_all_to_bq_mergeview"
  topic = var.pubsub_topic_id

  ack_deadline_seconds = 20
}
