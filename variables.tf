variable "app_name" {
  description = "The app name used for tagging infrastructure."
  type        = string
}

variable "aws_region" {
  description = "The AWS region in which the infrastructure will be provisioned."
  type        = string
}

variable "bucket_name" {
  type = string
}

variable "cloudfront_ttl" {
  description = "How many seconds an object remains in cache."
  type        = number
}

variable "create_secrets" {
  default     = true
  description = ""
  type        = bool
}

variable "domain_zone_id" {
  description = "DNS zone where host names will be created."
  type        = string
}

variable "environment" {
  description = "The environment in which this infrastructure will be provisioned."
  type        = string
}

variable "github_repo_url" {
  description = ""
  type        = string
}
