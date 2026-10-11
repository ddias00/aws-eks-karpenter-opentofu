output "cluster_name" { value = module.eks.cluster_name }
output "region" { value = var.region }
output "cluster_endpoint" { value = module.eks.cluster_endpoint }
output "cluster_ca" { value = module.eks.cluster_certificate_authority_data }
output "node_role_name" { value = module.karpenter.node_iam_role_name }
output "queue_name" { value = module.karpenter.queue_name }
