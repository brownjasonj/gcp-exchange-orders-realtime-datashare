variable "project_id" {
  description = "The GCP Project ID"
  type        = string
}

variable "region" {
  description = "The GCP Region"
  type        = string
}

variable "delay_in_seconds" {
  description = "The delay in seconds for the authorized view"
  type        = number
}

variable "src_dataset_id" {
  description = "The source BigQuery dataset ID where the bigquery table is to be created"
  type        = string
}

variable "src_bq_schema_file" {
  description = "The path to the BigQuery schema file"
  type        = string
}

variable "retention_days" {
  description = "The retention days for the BigQuery table"
  type        = number
}

variable "trgt_dataset_id" {
  description = "The target BigQuery dataset ID where the authorizedview will be created"
  type        = string
}

variable "pubsub_topic_id" {
  description = "The Pub/Sub topic ID"
  type        = string
}
