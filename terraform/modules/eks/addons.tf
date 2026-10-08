#EKS addon configuration
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.eks_cluster.name
  addon_name                  = "vpc-cni"
  addon_version               = var.cni_version
  resolve_conflicts_on_update = "OVERWRITE"
  service_account_role_arn    = aws_iam_role.vpc_cni_irsa.arn

  # Enforce Kubernetes NetworkPolicy (the Helm chart ships one per service)
  configuration_values = jsonencode({
    enableNetworkPolicy = "true"
  })
}

resource "aws_eks_addon" "core_dns" {
  cluster_name                = aws_eks_cluster.eks_cluster.name
  addon_name                  = "coredns"
  addon_version               = var.coredns_version
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.eks_cluster.name
  addon_name                  = "kube-proxy"
  addon_version               = var.kube_proxy_version
  resolve_conflicts_on_update = "OVERWRITE"
}

# Metrics API for the Horizontal Pod Autoscaler (community add-on, not installed on EKS by default)
resource "aws_eks_addon" "metrics_server" {
  cluster_name                = aws_eks_cluster.eks_cluster.name
  addon_name                  = "metrics-server"
  addon_version               = var.metrics_server_version
  resolve_conflicts_on_update = "OVERWRITE"
}
