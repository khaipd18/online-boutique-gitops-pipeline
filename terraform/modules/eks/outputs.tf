# Outputs for EKS Cluster Information
output "cluster_name" {
  description = "The name of the EKS cluster."
  value       = aws_eks_cluster.eks_cluster.name
}

output "cluster_version" {
  description = "The version of the EKS cluster."
  value       = aws_eks_cluster.eks_cluster.version
}

output "cluster_endpoint" {
  description = "The endpoint URL of the EKS cluster."
  value       = aws_eks_cluster.eks_cluster.endpoint
}

output "cluster_certificate_authority_data" {
  description = "The base64-encoded certificate authority data for the EKS cluster."
  value       = aws_eks_cluster.eks_cluster.certificate_authority[0].data
}

output "cluster_oidc_issuer_url" {
  description = "The OIDC issuer URL for the EKS cluster."
  value       = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
}

output "cluster_security_group_id" {
  description = "The security group ID associated with the EKS cluster."
  value       = aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id
}

# Output for Node Group Information
output "node_group_name" {
  description = "The name of the EKS node group."
  value       = aws_eks_node_group.eks_node_group.node_group_name
}

output "node_group_role_arn" {
  description = "The ARN of the IAM role associated with the EKS node group."
  value       = aws_iam_role.node_group.arn
}

output "node_group_status" {
  description = "The status of the EKS node group."
  value       = aws_eks_node_group.eks_node_group.status
}
