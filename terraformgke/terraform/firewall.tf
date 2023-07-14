resource "google_compute_firewall" "rules" {
  project = var.project_id
  name    = "allow-ssh"
  network = module.gcp-network.network_name
  allow {
    protocol = "tcp"
    ports    = ["22", "443"]
  }
  source_ranges = ["0.0.0.0/0"]
}
