variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "service_name" {
  description = "Cloud Run service name"
  type        = string
  default     = "noongil-backend"
}

variable "image" {
  description = "Container image URI to deploy to Cloud Run"
  type        = string
}

variable "allow_unauthenticated" {
  description = "Whether to allow unauthenticated invocations"
  type        = bool
  default     = true
}

variable "service_account_email" {
  description = "Optional service account for the Cloud Run service"
  type        = string
  default     = ""
}

variable "env_vars" {
  description = "Environment variables injected into the Cloud Run service"
  type        = map(string)
  default     = {}
}

variable "create_firestore" {
  description = "Whether Terraform should create the default Firestore database"
  type        = bool
  default     = false
}
