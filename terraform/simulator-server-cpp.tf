resource "google_artifact_registry_repository" "simulator_cpp_repo" {
  location      = var.region
  repository_id = "simulator-cpp-repo"
  description   = "Docker repository for Simulator Server C++"
  format        = "DOCKER"
  depends_on    = [google_project_service.artifact_registry_api]
}

locals {
  source_dir_cpp = "${path.module}/../simulator-server-cpp"

  # Hash sensitive files for rebuild logic
  src_files_hash_cpp  = sha1(join("", [for f in fileset("${local.source_dir_cpp}/src", "**") : filesha1("${local.source_dir_cpp}/src/${f}")]))
  cmake_hash_cpp      = filesha1("${local.source_dir_cpp}/CMakeLists.txt")
  dockerfile_hash_cpp = filesha1("${local.source_dir_cpp}/Dockerfile")
  sdk_dockerfile_hash = filesha1("${local.source_dir_cpp}/Dockerfile.sdk")

  composite_hash_cpp = sha1("${local.src_files_hash_cpp}-${local.cmake_hash_cpp}-${local.dockerfile_hash_cpp}-${local.sdk_dockerfile_hash}")

  image_name_cpp = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.simulator_cpp_repo.repository_id}/simulator-server-cpp:${local.composite_hash_cpp}"
  sdk_base_image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.simulator_cpp_repo.repository_id}/simulator-cpp-sdk-base:latest"
}

resource "null_resource" "build_sdk_base" {
  count = var.simulator_implementation == "cpp" ? 1 : 0
  triggers = {
    sdk_hash = local.sdk_dockerfile_hash
  }

  provisioner "local-exec" {
    command = <<EOT
      gcloud builds submit ${local.source_dir_cpp} \
        --config ${local.source_dir_cpp}/cloudbuild-sdk.yaml \
        --substitutions _TAG=${local.sdk_base_image} \
        --project ${var.project_id}
    EOT
  }

  depends_on = [
    google_artifact_registry_repository.simulator_cpp_repo,
    google_project_service.cloudbuild_api
  ]
}

data "google_project" "project" {}

resource "google_artifact_registry_repository_iam_member" "cloudbuild_registry_reader" {
  location   = google_artifact_registry_repository.simulator_cpp_repo.location
  repository = google_artifact_registry_repository.simulator_cpp_repo.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
}

resource "null_resource" "build_and_push_image_cpp" {
  count = var.simulator_implementation == "cpp" ? 1 : 0
  triggers = {
    image_hash = local.composite_hash_cpp
  }

  provisioner "local-exec" {
    command = <<EOT
      gcloud builds submit ${local.source_dir_cpp} \
        --config ${local.source_dir_cpp}/cloudbuild-app.yaml \
        --substitutions _TAG=${local.image_name_cpp},_SDK_BASE=${local.sdk_base_image} \
        --project ${var.project_id}
    EOT
  }

  depends_on = [
    null_resource.build_sdk_base,
    google_artifact_registry_repository_iam_member.cloudbuild_registry_reader,
    google_artifact_registry_repository.simulator_cpp_repo,
    google_project_service.cloudbuild_api
  ]
}

resource "google_cloud_run_v2_service" "simulator_server_cpp" {
  count    = var.simulator_implementation == "cpp" ? var.simulator_shards : 0
  name     = "simulator-server-cpp-${count.index}"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    containers {
      image = local.image_name_cpp
      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "PUBSUB_TOPIC"
        value = var.pubsub_topic
      }
      env {
        name  = "BIGQUERY_DATASET_ID"
        value = "paywall_datasets"
      }
      env {
        name  = "BIGQUERY_TABLE_ID"
        value = "bidask_all_staged"
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
          cpu    = "4000m" # C++ is efficient, but let's give it some power
          memory = "8192Mi"
        }
      }
      startup_probe {
        initial_delay_seconds = 60
        timeout_seconds       = 60
        period_seconds        = 10
        failure_threshold     = 10
        tcp_socket {
          port = 8080
        }
      }
    }
  }

  depends_on = [
    null_resource.build_and_push_image_cpp,
    google_project_service.run_api,
    google_pubsub_topic.pricing_topic
  ]
}

# Allow unauthenticated access
resource "google_cloud_run_service_iam_member" "simulator_server_cpp_public_access" {
  count    = var.simulator_implementation == "cpp" ? var.simulator_shards : 0
  location = google_cloud_run_v2_service.simulator_server_cpp[count.index].location
  service  = google_cloud_run_v2_service.simulator_server_cpp[count.index].name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
