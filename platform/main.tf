terraform {
  required_version = ">= 1.10.0, < 2.0.0"
  required_providers {
    helm = { source = "hashicorp/helm", version = "~> 2.17" }
  }
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
resource "helm_release" "karpenter" {
  name       = "karpenter"
  namespace  = "kube-system"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.6.3"
  wait       = true
  atomic     = true
  timeout    = 600
  values = [yamlencode({
    replicas     = 2
    nodeSelector = { workload = "system" }
    tolerations  = [{ key = "CriticalAddonsOnly", operator = "Exists", effect = "NoSchedule" }]
    settings     = { clusterName = local.infra.cluster_name, clusterEndpoint = local.infra.cluster_endpoint, interruptionQueue = local.infra.queue_name }
  })]
}
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.12.2"
  atomic     = true
  values = [yamlencode({
    replicas            = 2
    nodeSelector        = { workload = "system" }
    tolerations         = [{ key = "CriticalAddonsOnly", operator = "Exists", effect = "NoSchedule" }]
    podDisruptionBudget = { enabled = true, minAvailable = 1 }
  })]
}
