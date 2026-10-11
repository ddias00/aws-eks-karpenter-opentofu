data "aws_availability_zones" "available" { state = "available" }
locals {
  azs  = slice(data.aws_availability_zones.available.names, 0, 3)
  tags = { Project = var.cluster_name, ManagedBy = "OpenTofu" }
}
module "vpc" {
  source                 = "terraform-aws-modules/vpc/aws"
  version                = "6.0.1"
  name                   = var.cluster_name
  cidr                   = "10.42.0.0/16"
  azs                    = local.azs
  private_subnets        = ["10.42.0.0/20", "10.42.16.0/20", "10.42.32.0/20"]
  public_subnets         = ["10.42.128.0/24", "10.42.129.0/24", "10.42.130.0/24"]
  enable_nat_gateway     = true
  one_nat_gateway_per_az = true
  single_nat_gateway     = false
  enable_dns_hostnames   = true
  public_subnet_tags     = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags    = { "kubernetes.io/role/internal-elb" = "1", "karpenter.sh/discovery" = var.cluster_name }
  tags                   = local.tags
}
module "eks" {
  source                                   = "terraform-aws-modules/eks/aws"
  version                                  = "21.4.0"
  name                                     = var.cluster_name
  kubernetes_version                       = var.kubernetes_version
  vpc_id                                   = module.vpc.vpc_id
  subnet_ids                               = module.vpc.private_subnets
  endpoint_public_access                   = true
  endpoint_private_access                  = true
  endpoint_public_access_cidrs             = var.api_allowed_cidrs
  enable_cluster_creator_admin_permissions = true
  addons = {
    vpc-cni                = { before_compute = true }
    eks-pod-identity-agent = { before_compute = true }
    kube-proxy             = {}
    coredns                = {}
  }
  eks_managed_node_groups = {
    system = {
      instance_types = ["m6i.large"]
      min_size       = 3
      max_size       = 3
      desired_size   = 3
      labels         = { "workload" = "system" }
      taints         = { system = { key = "CriticalAddonsOnly", value = "true", effect = "NO_SCHEDULE" } }
    }
  }
  node_security_group_tags = { "karpenter.sh/discovery" = var.cluster_name }
  tags                     = local.tags
}
module "karpenter" {
  source       = "terraform-aws-modules/eks/aws//modules/karpenter"
  version      = "21.4.0"
  cluster_name = module.eks.cluster_name
  namespace    = "kube-system"
  tags         = local.tags
}
