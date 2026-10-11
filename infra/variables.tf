variable "region" {
  type    = string
  default = "us-east-1"
}
variable "cluster_name" {
  type    = string
  default = "eks-karpenter-demo"
}
variable "kubernetes_version" {
  type    = string
  default = "1.33"
}
variable "api_allowed_cidrs" {
  description = "IPs autorizados a acessar a API pública do EKS (ex.: seu IP/32)."
  type        = list(string)
  validation {
    condition     = length(var.api_allowed_cidrs) > 0 && !contains(var.api_allowed_cidrs, "0.0.0.0/0") && alltrue([for c in var.api_allowed_cidrs : can(cidrnetmask(c))])
    error_message = "Informe CIDRs IPv4 restritos; 0.0.0.0/0 não é permitido."
  }
}
