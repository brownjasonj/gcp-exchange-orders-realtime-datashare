resource "google_artifact_registry_repository" "simulator_rust_repo" {
  location      = var.region
  repository_id = "simulator-rust-repo"
  description   = "Docker repository for Simulator Server Rust"
  format        = "DOCKER"
  depends_on    = [google_project_service.artifact_registry_api]
}

locals {
  source_dir_rust = "${path.module}/../simulator-server-rust"

  # Hash sensitive files for rebuild logic
  src_files_hash_rust  = sha1(join("", [for f in fileset("${local.source_dir_rust}/src", "**") : filesha1("${local.source_dir_rust}/src/${f}")]))
  package_hash_rust    = filesha1("${local.source_dir_rust}/Cargo.toml")
  dockerfile_hash_rust = filesha1("${local.source_dir_rust}/Dockerfile")
  config_hash_rust     = filesha1("${local.source_dir_rust}/config.json")

  composite_hash_rust = sha1("${local.src_files_hash_rust}-${local.package_hash_rust}-${local.dockerfile_hash_rust}-${local.config_hash_rust}")

  image_name_rust = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.simulator_rust_repo.repository_id}/simulator-server-rust:${local.composite_hash_rust}"
}

resource "null_resource" "build_and_push_image_rust" {
  count = var.simulator_implementation == "rust" ? 1 : 0
  triggers = {
    image_hash = local.composite_hash_rust
  }

  provisioner "local-exec" {
    command = <<EOT
      gcloud builds submit ${local.source_dir_rust} \
        --tag ${local.image_name_rust} \
        --project ${var.project_id}
    EOT
  }

  depends_on = [
    google_artifact_registry_repository.simulator_rust_repo,
    google_project_service.cloudbuild_api
  ]
}

resource "google_cloud_run_v2_service" "simulator_server_rust" {
  count    = var.simulator_implementation == "rust" ? var.simulator_shards : 0
  name     = "simulator-server-rust-${count.index}"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    containers {
      image = local.image_name_rust
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
      env {
        name  = "SHARD_INDEX"
        value = count.index
      }
      env {
        name  = "TOTAL_SHARDS"
        value = var.simulator_shards
      }
      ports {
        container_port = 8080
      }
      resources {
        limits = {
          cpu    = "2000m"
          memory = "8192Mi"
        }
      }
      startup_probe {
        initial_delay_seconds = 5
        timeout_seconds       = 5
        period_seconds        = 5
        failure_threshold     = 20
        tcp_socket {
          port = 8080
        }
      }
    }
  }

  depends_on = [
    null_resource.build_and_push_image_rust,
    google_project_service.run_api,
    google_pubsub_topic.pricing_topic
  ]
}

# Allow unauthenticated access
resource "google_cloud_run_service_iam_member" "simulator_server_rust_public_access" {
  count    = var.simulator_implementation == "rust" ? var.simulator_shards : 0
  location = google_cloud_run_v2_service.simulator_server_rust[count.index].location
  service  = google_cloud_run_v2_service.simulator_server_rust[count.index].name
  role     = "roles/run.invoker"
  member   = "allUsers"

  depends_on = [
    google_cloud_run_v2_service.simulator_server_rust
  ]
}
