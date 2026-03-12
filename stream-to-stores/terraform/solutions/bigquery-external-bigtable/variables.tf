variable "project_id" {
  description = "The GCP Project ID"
  type        = string
}

variable "region" {
  description = "The GCP Region"
  type        = string
}

variable "trgt_dataset_id" {
  description = "The target BigQuery dataset ID where the authorizedview will be created"
  type        = string
}
