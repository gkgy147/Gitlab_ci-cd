module "cloud_router" {
  source  = "terraform-google-modules/cloud-router/google"
  version = "~> 5.0"
  project = var.project_id # Replace this with your project ID in quotes
  name    = "my-cloud-router"
  network = module.gcp-network.network_name
  region  = var.region

  nats = [{
    name = "my-nat-gateway"
  }]
}
