
terraform {
  backend "gcs" {
    # 
    # given these attributes cannot include variables these will
    # be injected in via the config.gcs.tfbackend.....
    # 
    # bucket = "emea-6ek1muhc-project-bucket"
    # prefix = "terraform/dev"
  }
}

