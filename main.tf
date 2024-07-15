variable "gcp-creds" {
  default = ""
}

variable "gcp-proj" {
  default = ""
}

variable "gcp-region" {
  default = "asia-southeast2"
}

variable "gcp-zone" {
  default = "asia-southeast2-a"
}

terraform {
  required_providers {
    google = {
        source = "hashicorp/google"
        version = "5.37.0"
    }
  }
}

provider "google" {
  alias = "oprek"
  project = var.gcp-proj
  region = var.gcp-region
  zone = var.gcp-zone
  credentials = var.gcp-creds
}

resource "google_compute_network" "gke-vpc" {
  provider = google.oprek
  name = "gke-vpc"
  routing_mode = "REGIONAL"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "gke-public_subnet" {
  provider = google.oprek
  name = "gke-public-subnet"
  ip_cidr_range = "10.0.0.0/24"
  network = google_compute_network.gke-vpc.id

}

resource "google_compute_subnetwork" "gke-private_subnet" {
  provider = google.oprek
  name = "gke-private-subnet"
  ip_cidr_range = "10.0.1.0/24"
  network = google_compute_network.gke-vpc.id
  private_ip_google_access = true

  secondary_ip_range = [ 
    {
      range_name = "gke-private-subnet-pods"
      ip_cidr_range = "10.4.0.0/14"
    },
    {
      range_name = "gke-private-subnet-services"
      ip_cidr_range = "10.1.32.0/20"
    }
   ]
}

resource "google_compute_firewall" "gke-bastion_firewall" {
  provider = google.oprek
  name    = "gke-bastion-fw"
  network = google_compute_network.gke-vpc.id

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = [ "0.0.0.0/0" ]
  target_tags = ["bastion"]
}


resource "google_service_account" "gke-bastion-sa" {
  provider = google.oprek
  account_id = "gke-bastion-sa"
  display_name = "GCloud CLI SA on Compute Engine"
}


resource "google_project_iam_binding" "gke_bastion_developer" {
  
  provider = google.oprek
  project = var.gcp-proj

  role    = "roles/container.developer"
  members = [
    "serviceAccount:${google_service_account.gke-bastion-sa.email}",
    # Add other members as needed
  ]
  
  condition {
    title       = "GKE Cluster Only"
    description = "Only has access to the GKE cluster"
    expression  = "resource.hasTagKey('${var.gcp-proj}/${google_tags_tag_key.gke-tag.short_name}')"
  }
}



resource "google_compute_router" "gke_node_pool_nat_router" {
  provider = google.oprek
  name     = "gke-node-pool-nat-router"
  network  = google_compute_network.gke-vpc.name

}

resource "google_compute_router_nat" "nat" {
  provider = google.oprek
  name = "gke-node-pool-nat-router"
  router = google_compute_router.gke_node_pool_nat_router.name
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  subnetwork {
    name = google_compute_subnetwork.gke-private_subnet.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
  log_config {
    enable = false
    filter = "ALL"
  }
  nat_ip_allocate_option = "AUTO_ONLY"
}

resource "google_tags_tag_key" "gke-tag" {
    provider = google.oprek
    parent      = "projects/${var.gcp-proj}"
    short_name  = "gke-cluster"
    description = ""
}

resource "google_tags_tag_value" "gke-tag-value" {
    provider = google.oprek
    parent = google_tags_tag_key.gke-tag.id
    short_name = "gke-cluster-true"
    description = "It's True"
}


resource "google_tags_location_tag_binding" "gke-tag-value-binding" {
    provider = google.oprek
    parent = "//container.googleapis.com/${google_container_cluster.gke-cluster.id}"
    tag_value = google_tags_tag_value.gke-tag-value.id
    location = var.gcp-zone
}
resource "google_compute_instance" "gke-bastion_instance" {
  provider = google.oprek
  name = "bastion"
  machine_type = "e2-standard-2"
  zone = var.gcp-zone
  allow_stopping_for_update = true
  network_interface {
    network = google_compute_network.gke-vpc.id
    subnetwork = google_compute_subnetwork.gke-public_subnet.id
    network_ip = "10.0.0.10"
    access_config {
      // Ephemeral public IP
    }
  }
  tags = [ "bastion" ]
  boot_disk {
    auto_delete = true
    device_name = "gke-bastion-instance"

    initialize_params {
      image = "projects/ubuntu-os-cloud/global/images/ubuntu-2004-focal-v20231130"
      size  = 10
      type  = "pd-balanced"
    }
  }
  service_account{
    email  = google_service_account.gke-bastion-sa.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata_startup_script = file("bastion-startup.sh")
}

resource "google_container_cluster" "gke-cluster" {
  deletion_protection = false
  provider = google.oprek
  location = var.gcp-zone
  name = "gke-cluster"
  min_master_version = "1.27"
  remove_default_node_pool = true
  initial_node_count = 1
  
  
  network = google_compute_network.gke-vpc.id
  subnetwork = google_compute_subnetwork.gke-private_subnet.id
  networking_mode = "VPC_NATIVE"

  
  network_policy {
    enabled = true 
  }

  addons_config {
    network_policy_config {
      disabled = false
    }
  }

  ip_allocation_policy {
    cluster_secondary_range_name = google_compute_subnetwork.gke-private_subnet.secondary_ip_range[0].range_name
    services_secondary_range_name = google_compute_subnetwork.gke-private_subnet.secondary_ip_range[1].range_name
  }
  private_cluster_config {
    enable_private_nodes = true
    enable_private_endpoint = true
    master_ipv4_cidr_block = "172.16.0.16/28"
  }
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block = google_compute_subnetwork.gke-public_subnet.ip_cidr_range
    }
  }
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }
  
}

resource "google_container_node_pool" "gke-cluster-node-pool" {
  provider = google.oprek
  name = google_container_cluster.gke-cluster.name
  node_count = 2
  cluster = google_container_cluster.gke-cluster.id

  version = "1.27.4-gke.900"
  node_config {
    spot = true
    machine_type = "e2-standard-2"
    disk_size_gb = 20
    disk_type = "pd-standard"
    image_type = "UBUNTU_CONTAINERD"
    # service_account = google_service_account.gke-bastion-sa.email

  }
}
# resource "google_container_node_pool_iam_binding" "gke_bastion_user" {
#   node_pool_id       = google_container_node_pool.my_node_pool.id
#   role               = "roles/container.user"
#   members            = [ "serviceAccount:${google_service_account.gke-bastion-sa.email}" ]
# }