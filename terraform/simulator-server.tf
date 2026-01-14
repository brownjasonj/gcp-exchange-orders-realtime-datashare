resource "google_project_service" "run_api" {
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "artifact_registry_api" {
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudbuild_api" {
  service            = "cloudbuild.googleapis.com"
  disable_on_destroy = false
}

resource "google_artifact_registry_repository" "simulator_repo" {
  location      = var.region
  repository_id = "simulator-repo"
  description   = "Docker repository for Simulator Server"
  format        = "DOCKER"
  depends_on    = [google_project_service.artifact_registry_api]
}

locals {
  source_dir = "${path.module}/../simulator-server"
  # Hash sensitive files to determine if rebuild is needed
  # We intentionally exclude node_modules and dist from the hash
  src_files_hash  = sha1(join("", [for f in fileset("${local.source_dir}/src", "**") : filesha1("${local.source_dir}/src/${f}")]))
  package_hash    = filesha1("${local.source_dir}/package.json")
  tsconfig_hash   = filesha1("${local.source_dir}/tsconfig.json")
  dockerfile_hash = filesha1("${local.source_dir}/Dockerfile")
  config_hash     = filesha1("${local.source_dir}/config.json")

  composite_hash = sha1("${local.src_files_hash}-${local.package_hash}-${local.tsconfig_hash}-${local.dockerfile_hash}-${local.config_hash}")

  image_name = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.simulator_repo.repository_id}/simulator-server:${local.composite_hash}"
}

resource "null_resource" "build_and_push_image" {
  triggers = {
    image_hash = local.composite_hash
  }

  provisioner "local-exec" {
    command = <<EOT
      gcloud builds submit ${local.source_dir} \
        --tag ${local.image_name} \
        --project ${var.project_id}
    EOT
  }

  depends_on = [
    google_artifact_registry_repository.simulator_repo,
    google_project_service.cloudbuild_api
  ]
}

resource "google_cloud_run_v2_service" "simulator_server" {
  name     = "simulator-server"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    containers {
      image = local.image_name
      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "PUBSUB_TOPIC"
        value = var.pubsub_topic
      }
      env {
        name  = "CONFIG_PATH"
        value = "./config.json"
      }
      ports {
        container_port = 8080
      }
    }
  }

  depends_on = [
    null_resource.build_and_push_image,
    google_project_service.run_api,
    google_pubsub_topic.pricing_topic
  ]
}

# Allow unauthenticated access to support public UI access and WebSockets
# Resource commented out due to Organization Policy blocking allUsers
# resource "google_cloud_run_service_iam_member" "simulator_server_public_access" {
#   location = google_cloud_run_v2_service.simulator_server.location
#   service  = google_cloud_run_v2_service.simulator_server.name
#   role     = "roles/run.invoker"
#   member   = "allUsers"

#   depends_on = [
#     google_cloud_run_v2_service.simulator_server
#   ]
# }

