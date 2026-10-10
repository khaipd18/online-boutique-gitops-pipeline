# Control plane log group. EKS would create it on its own with no retention and leave it behind on destroy,
# so Terraform creates it first and owns its lifecycle
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.log_retention_days
}

resource "aws_eks_cluster" "eks_cluster" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.vpc_config.subnet_ids
    endpoint_private_access = var.vpc_config.endpoint_private_access
    endpoint_public_access  = var.vpc_config.endpoint_public_access
    public_access_cidrs     = var.vpc_config.public_access_cidrs
  }
  # Access entries let IAM principals other than the creator use the cluster (and the EKS console) without the aws-auth ConfigMap
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  version                   = var.k8s_version
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
    aws_cloudwatch_log_group.cluster,
  ]

}

# Read-only Kubernetes access for the roles people use in the AWS console, so the console can list pods and nodes.
# AmazonEKSAdminViewPolicy covers every resource (nodes included, Secrets too); AmazonEKSViewPolicy does not include nodes
resource "aws_eks_access_entry" "console_viewer" {
  for_each      = toset(var.console_viewer_role_arns)
  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = each.value
}

resource "aws_eks_access_policy_association" "console_viewer" {
  for_each      = aws_eks_access_entry.console_viewer
  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = each.value.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminViewPolicy"

  access_scope {
    type = "cluster"
  }
}
