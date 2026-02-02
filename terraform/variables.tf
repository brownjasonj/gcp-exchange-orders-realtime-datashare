variable "project_id" {
  description = "The GCP Project ID where resources will be created"
  type        = string
}

variable "pubsub_topic" {
  description = "The name of the Pub/Sub topic to create"
  type        = string
  default     = "pricing-topic"
}

variable "region" {
  description = "The GCP region where resources will be created"
  type        = string
  default     = "us-central1"
}

variable "network_vpc_name" {
  description = "The GCP network where resources will be created"
  type        = string
  default     = ""
}

variable "subnetwork_name" {
  description = "The GCP subnetwork where resources will be created"
  type        = string
  default     = ""
}

variable "simulator_shards" {
  description = "Number of simulator shards to deploy"
  type        = number
  default     = 10
}

variable "simulator_implementation" {
  description = "The implementation of the simulator server to deploy. Options: 'node' or 'rust'"
  type        = string
  default     = "node"
  validation {
    condition     = contains(["node", "rust"], var.simulator_implementation)
    error_message = "The simulator_implementation must be either 'node' or 'rust'."
  }
}
