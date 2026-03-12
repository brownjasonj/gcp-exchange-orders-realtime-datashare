output "simulator_ui_url" {
  description = "The public URL of the Simulator UI (GCF)"
  value       = google_cloudfunctions2_function.simulator_ui.url
}

output "simulator_ui_cloud_run_url" {
  description = "Direct Cloud Run URL for the Simulator UI (Recommended for SPAs)"
  value       = google_cloudfunctions2_function.simulator_ui.service_config[0].uri
}

output "project_id" {
  value = var.project_id
}

output "backend_urls" {
  value = google_cloud_run_v2_service.simulator_server_cpp[*].uri
}
