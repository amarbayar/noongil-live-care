output "cloud_run_service_url" {
  description = "HTTPS URL of the deployed Cloud Run backend"
  value       = google_cloud_run_v2_service.backend.uri
}
