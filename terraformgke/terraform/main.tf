
terraform {
  backend "gcs" {
    bucket = "grobert-tf-state-staging"
    prefix = "terraform/state"
  }
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.16"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.9.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "1.14.0"
    }
  }
}

provider "helm" {
  kubernetes {
    host                   = "https://${module.gke.endpoint}"
    cluster_ca_certificate = base64decode(module.gke.ca_certificate)
    token                  = data.google_client_config.default.access_token
  }
}

provider "kubectl" {
  host                   = module.gke.endpoint
  cluster_ca_certificate = base64decode(module.gke.ca_certificate)
  token                  = data.google_client_config.default.access_token
  load_config_file       = false
}

module "gke_auth" {
  source = "terraform-google-modules/kubernetes-engine/google//modules/auth"
  version = "24.1.0"
  depends_on   = [module.gke]
  project_id   = var.project_id
  location     = module.gke.location
  cluster_name = module.gke.name
}

resource "local_file" "kubeconfig" {
  content  = module.gke_auth.kubeconfig_raw
  filename = "kubeconfig"
}

data "google_client_config" "default" {}

module "gcp-network" {
  source       = "terraform-google-modules/network/google"
  version      = "~> 7.0"
  project_id   = var.project_id
  network_name = var.network

  subnets = [
    {
      subnet_name   = var.subnetwork
      subnet_ip     = "10.10.0.0/16"
      subnet_region = var.region
    },
  ]

  secondary_ranges = {
     (var.subnetwork) = [
      {
        range_name    = var.ip_range_pods_name
        ip_cidr_range = "10.20.0.0/16"
      },
      {
        range_name    = var.ip_range_services_name
        ip_cidr_range = "10.30.0.0/16"
      }
    ]
  }
}

provider "kubernetes" {
  host                   = "https://${module.gke.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.ca_certificate)
}
  

module "gke" {
  source                          = "terraform-google-modules/kubernetes-engine/google//modules/private-cluster"
  version                         = "24.1.0"
  project_id                      = var.project_id
  name                            = var.cluster_name
  regional                        = false
  region                          = var.region
  zones                           = var.zones 
  network                         = module.gcp-network.network_name
  subnetwork                      = module.gcp-network.subnets_names[0]
  ip_range_pods                   = var.ip_range_pods_name
  ip_range_services               = var.ip_range_services_name
  horizontal_pod_autoscaling      = true
  enable_vertical_pod_autoscaling = true
  enable_private_nodes            = true
  
  node_pools = [
    {
      name                      = "node-pool"
      machine_type              = "e2-standard-4"
      min_count                 = 1
      max_count                 = 2
      disk_size_gb              = 30
      auto_repair               = true
      initial_node_count        = 1
      auto_upgrade              = true
    },
  ]
}
