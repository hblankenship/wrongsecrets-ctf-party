# Uncomment for ssl using ACM
module "acm_balancer" {
  source = "terraform-aws-modules/acm/aws"

  count = var.balancer_domain_name != "" ? 1 : 0

  validation_method = "DNS"

  domain_name = var.balancer_domain_name
  zone_id     = var.hosted_zone_id

  subject_alternative_names = [
    "*.${var.balancer_domain_name}"
  ]

  wait_for_validation = true
}

module "acm_ctfd" {
  source = "terraform-aws-modules/acm/aws"

  count = var.ctfd_domain_name != "" ? 1 : 0

  validation_method = "DNS"

  domain_name = var.ctfd_domain_name
  zone_id     = var.hosted_zone_id

  subject_alternative_names = [
    "*.${var.ctfd_domain_name}"
  ]

  wait_for_validation = true
}
