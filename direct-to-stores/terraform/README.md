gcloud auth login

gcloud auth application-default login

terraform init -backend-config=config.gcs.tfbackend

terraform apply -auto-approve
