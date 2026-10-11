terraform {
  required_version = ">= 1.10.0, < 2.0.0"
  required_providers {
    helm = { source = "hashicorp/helm", version = "~> 2.17" }
  }
}
variable "ami_alias" {
  description = "Release AL2023 validada na região. Fixe uma release antes de produção."
  type        = string
  default     = "al2023@latest"
}
data "terraform_remote_state" "infra" {
  backend = "local"
  config  = { path = "${path.module}/../infra/terraform.tfstate" }
}
locals { infra = data.terraform_remote_state.infra.outputs }
provider "helm" {
  kubernetes {
    host                   = local.infra.cluster_endpoint
    cluster_ca_certificate = base64decode(local.infra.cluster_ca)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.infra.cluster_name, "--region", local.infra.region]
    }
  }
}
resource "helm_release" "demo" {
  name             = "ha-demo"
  namespace        = "ha-demo"
  create_namespace = true
  chart            = "${path.module}/chart"
  timeout          = 900
  atomic           = true
  values           = [yamlencode({ clusterName = local.infra.cluster_name, nodeRole = local.infra.node_role_name, amiAlias = var.ami_alias })]
}
