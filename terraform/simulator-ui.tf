resource "null_resource" "build_simulator_ui" {
  triggers = {
    src_hash          = sha1(join("", [for f in fileset("${path.module}/../simulator-ui/src", "**") : filesha1("${path.module}/../simulator-ui/src/${f}")]))
    package_json_hash = filesha1("${path.module}/../simulator-ui/package.json")
  }

  provisioner "local-exec" {
    command = "cd ${path.module}/../simulator-ui && npm install && npm run build"
  }
}

data "archive_file" "simulator_ui_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../simulator-ui"
  output_path = "${path.module}/files/simulator-ui.zip"
  excludes    = ["node_modules", ".git", ".angular", "package-lock.json"] # Can exclude src/ to save space as we only need dist/ and server.js
  depends_on = [
    null_resource.build_simulator_ui
  ]
}

resource "google_storage_bucket_object" "simulator_ui_object" {
  name   = "simulator-ui-${data.archive_file.simulator_ui_zip.output_md5}.zip"
  bucket = google_storage_bucket.function_bucket.name
  source = data.archive_file.simulator_ui_zip.output_path
  depends_on = [
    data.archive_file.simulator_ui_zip
  ]
}

resource "google_cloudfunctions2_function" "simulator_ui" {
  name        = "simulator-ui"
  location    = var.region
  description = "Simulator UI Function"

  build_config {
    runtime     = "nodejs20"
    entry_point = "app"
    source {
      storage_source {
        bucket = google_storage_bucket.function_bucket.name
        object = google_storage_bucket_object.simulator_ui_object.name
      }
    }
  }

  service_config {
    max_instance_count = 1
    available_memory   = "256M"
    timeout_seconds    = 60
    environment_variables = {
      PROJECT_ID = var.project_id
      API_URL    = google_cloud_run_v2_service.simulator_server.uri
    }
  }

  depends_on = [
    google_cloud_run_v2_service.simulator_server,
    google_storage_bucket_object.simulator_ui_object
  ]
}

# Allow unauthenticated access to support public UI access and WebSockets
# Resource commented out due to Organization Policy blocking allUsers
# resource "google_cloud_run_service_iam_member" "simulator_ui_public_access" {
#   location = google_cloudfunctions2_function.simulator_ui.location
#   service  = google_cloudfunctions2_function.simulator_ui.name
#   role     = "roles/run.invoker"
#   member   = "allUsers"
# 
#   depends_on = [
#     google_cloudfunctions2_function.simulator_ui
#   ]
# }