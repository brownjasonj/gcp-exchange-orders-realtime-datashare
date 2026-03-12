variable "project_id" {
  type        = string
  description = "The GCP project ID"
}

variable "region" {
  type        = string
  description = "The GCP region"
}

variable "delay_in_seconds" {
  type        = number
  description = "The delay in seconds"
}

variable "trgt_dataset_id" {
  type        = string
  description = "The BigQuery dataset ID"
}

variable "topic_id" {
  type        = string
  description = "The Pub/Sub topic ID"
}

variable "function_bucket_name" {
  type        = string
  description = "The GCS bucket for the function source code"
}
