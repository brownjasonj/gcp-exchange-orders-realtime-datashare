resource "google_storage_bucket" "function_bucket" {
  name                        = "${var.project_id}-function-source"
  location                    = "US"
  uniform_bucket_level_access = true
}
