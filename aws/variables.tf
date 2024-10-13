variable "region" {
  description = "The AWS region to use"
  type        = string
  default     = "eu-west-1"
}
variable "balancer_domain_name" {
  description = "The domain name to use"
  type        = string
  default     = ""
}

variable "ctfd_domain_name" {
  description = "The domain name to use"
  type        = string
  default     = ""
}

variable "hosted_zone_id" {
  description = "The ID of the Route53 Hosted Zone to use"
  type        = string
  default     = ""
}

variable "cluster_version" {
  description = "The EKS cluster version to use"
  type        = string
  default     = "1.30"
}

variable "cluster_name" {
  description = "The EKS cluster name"
  type        = string
  default     = "wrongsecrets-exercise-cluster"
}

variable "extra_allowed_ip_ranges" {
  description = "Allowed IP ranges in addition to creator IP"
  type        = list(string)
  default     = []
}

variable "state_bucket_arn" {
  description = "ARN of the state bucket to grant access to the s3 user"
  type        = string
}
