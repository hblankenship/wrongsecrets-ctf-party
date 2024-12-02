terraform {
  # Set your region and bucket name (output from shared state) in the placeholder below
  # Then uncomment and apply!
  # backend "s3" {
  #   region = "eu-west-1"                            # Change if desired
  #   bucket = "terraform-20230310093750024400000001" # Put your bucket name here
  #   key    = "wrongsecrets/terraform.tfstate"       # Change if desired
  # }
}

locals {
  vpc_cidr = "172.16.0.0/16"

  private_subnet_1_cidr = "172.16.1.0/24"
  private_subnet_2_cidr = "172.16.2.0/24"
  private_subnet_3_cidr = "172.16.3.0/24"

  public_subnet_1_cidr = "172.16.4.0/24"
  public_subnet_2_cidr = "172.16.5.0/24"
  public_subnet_3_cidr = "172.16.6.0/24"
}

provider "aws" {
  region = var.region
}

provider "random" {}

provider "http" {}

data "http" "ip" {
  url = "http://ipecho.net/plain"
}

data "aws_availability_zones" "available" {}


module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.16.0"

  name                 = "${var.cluster_name}-vpc"
  cidr                 = local.vpc_cidr
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = [local.private_subnet_1_cidr, local.private_subnet_2_cidr, local.private_subnet_3_cidr]
  public_subnets       = [local.public_subnet_1_cidr, local.public_subnet_2_cidr, local.public_subnet_3_cidr]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }
}


module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.30.1"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_addons = {
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn
      configuration_values = jsonencode({
        defaultStorageClass = {
          enabled = true
        }
      })
    }
  }

  cluster_upgrade_policy = {
    support_type = "STANDARD"
  }


  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  cluster_endpoint_public_access_cidrs = compact(concat(["${data.http.ip.response_body}/32"], var.extra_allowed_ip_ranges))

  enable_irsa = true

  enable_cluster_creator_admin_permissions = true

  create_cloudwatch_log_group            = true
  cluster_enabled_log_types              = ["api", "audit", "authenticator"]
  cloudwatch_log_group_retention_in_days = 14 #it's a ctf , we don't need unnecessary costs!

  # apply when available: iam_role_permissions_boundary = "arn:aws:iam::${local.account_id}:policy/service-user-creation-permission-boundary"
  eks_managed_node_group_defaults = {
    instance_types = ["m5a.xlarge"]
    block_device_mappings = [
      {
        device_name = "/dev/xvda"
        ebs = {
          volume_size           = 200
          volume_type           = "gp3"
          iops                  = 3000
          throughput            = 150
          delete_on_termination = true
        }
      }
    ]
    metadata_options = {
      http_tokens = "required",
    }

    iam_role_additional_policies = {
      AmazonEKSWorkerNodePolicy : "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
      AmazonEKS_CNI_Policy : "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
      AmazonEC2ContainerRegistryReadOnly : "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
      AmazonSSMManagedInstanceCore : "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
      AmazonEKSVPCResourceController : "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController",
      AmazonEBSCSIDriverPolicy : "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    }
  }

  eks_managed_node_groups = {
    bottlerocket_default = {
      name          = "wrongsecrets-ctf"
      min_size      = 3
      max_size      = 50
      desired_size  = 3
      capacity_type = "ON_DEMAND"

      ami_type = "BOTTLEROCKET_x86_64"
      platform = "bottlerocket"
    }
  }

  node_security_group_additional_rules = {
    aws_lb_controller_webhook = {
      description                   = "Cluster API to AWS LB Controller webhook"
      protocol                      = "all"
      from_port                     = 9443
      to_port                       = 9443
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  tags = {
    Environment                                               = "test"
    Application                                               = "wrongsecrets"
    "k8s.io/cluster-autoscaler/wrongsecrets-exercise-cluster" = "owned"
    "k8s.io/cluster-autoscaler/enabled"                       = true
  }
}

# Cluster Autoscaler IRSA
module "cluster_autoscaler_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.46"


  role_name                        = "wrongsecrets-cluster-autoscaler"
  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_ids   = [module.eks.cluster_name]

  oidc_providers = {
    cluster = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:cluster-autoscaler"]
    }
  }
}

module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.46"

  role_name             = "wrongsecrets-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

module "load_balancer_controller_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.46"

  role_name                              = "wrongsecrets-load-balancer-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

module "external_dns_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.46"

  role_name                  = "external-dns"
  attach_external_dns_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:external-dns"]
    }
  }
}
