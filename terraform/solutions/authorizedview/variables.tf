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
  description = "The source BigQuery dataset ID"
  type        = string
}

variable "src_table_id" {
  description = "The source BigQuery table ID"
  type        = string
}

variable "trgt_dataset_id" {
  description = "The target BigQuery dataset ID where the view will be created"
  type        = string
}
