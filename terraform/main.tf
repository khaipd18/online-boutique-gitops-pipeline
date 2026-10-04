module "vpc" {
  source           = "./modules/vpc"
  vpc_subnet_az_id = var.az_ids
  vpc_cidr         = var.vpc_cidr
}

module "ecr" {
  source                = "./modules/ecr"
  scan_on_push          = var.scan_on_push
  force_delete          = var.force_delete
  image_tag_mutability  = var.image_tag_mutability
  repository_names      = var.repository_names
  allow_push_principals = var.allow_push_principals
  allow_pull_principals = var.allow_pull_principals
}
# This module creates an IAM role that can be assumed by GitHub Actions using OIDC
resource "aws_iam_openid_connect_provider" "github_core" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # thumbprint_list omitted: IAM verifies GitHub's OIDC endpoint against its trusted root CA library
}

# The policy document for ECR permissions is defined separately to keep the role definition clean and focused on the trust relationship.
data "aws_iam_policy_document" "ecr_permissions" {
  # Common permissions for Docker to login (Resource is required to be "*")
  statement {
    sid       = "GetAuthorizationToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  # Pull and push permissions for the specified ECR repositories
  statement {
    sid    = "AllowPushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload"
    ]
    resources = module.ecr.repository_arns
  }
}

resource "aws_iam_policy" "ecr_push_policy" {
  name        = "GitHubActions-ECR-Push-Policy"
  description = "Permissions for GitHub Actions to manage ECR images"
  policy      = data.aws_iam_policy_document.ecr_permissions.json
}

locals {
  github_oidc_repos = compact([var.github_repo, var.github_repo_immutable])
}

# Image builds run only from main (push or manual run)
module "github_oidc_role_ecr" {
  source              = "./modules/github-oidc-role"
  role_name           = "github-actions-ecr-oidc-role"
  github_repos        = local.github_oidc_repos
  allowed_subjects    = ["ref:refs/heads/main"]
  oidc_provider_arn   = aws_iam_openid_connect_provider.github_core.arn
  ecr_repository_arns = module.ecr.repository_arns
  custom_policy_arns  = [aws_iam_policy.ecr_push_policy.arn]
}

data "aws_caller_identity" "current" {}

# Terraform state management and policies for GitHub Actions to access S3 and DynamoDB and
data "aws_iam_policy_document" "terraform_state_permissions" {
  statement {
    sid     = "AllowS3StateManagement"
    effect  = "Allow"
    actions = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [
      "arn:aws:s3:::${var.tf_state_bucket}",
      "arn:aws:s3:::${var.tf_state_bucket}/*"
    ]
  }

  statement {
    sid       = "AllowDynamoDBLocking"
    effect    = "Allow"
    actions   = ["dynamodb:DescribeTable", "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = ["arn:aws:dynamodb:${var.region}:${data.aws_caller_identity.current.account_id}:table/${var.tf_state_lock_table}"]
  }
}

# Read-only state access for terraform plan on pull requests (plan runs with -lock=false, so no lock writes)
data "aws_iam_policy_document" "terraform_state_read_permissions" {
  statement {
    sid       = "AllowS3StateRead"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetObject"]
    resources = ["arn:aws:s3:::${var.tf_state_bucket}", "arn:aws:s3:::${var.tf_state_bucket}/*"]
  }

  statement {
    sid       = "AllowDynamoDBStateDigestRead"
    effect    = "Allow"
    actions   = ["dynamodb:DescribeTable", "dynamodb:GetItem"]
    resources = ["arn:aws:dynamodb:${var.region}:${data.aws_caller_identity.current.account_id}:table/${var.tf_state_lock_table}"]
  }
}

resource "aws_iam_policy" "terraform_state_read_policy" {
  name        = "GitHubActions-Terraform-State-Read-Policy"
  description = "Read-only access to the Terraform state for terraform plan on pull requests"
  policy      = data.aws_iam_policy_document.terraform_state_read_permissions.json
}

resource "aws_iam_policy" "terraform_state_policy" {
  name        = "GitHubActions-Terraform-State-Policy"
  description = "Permissions for GitHub Actions to manage Terraform state in S3 and DynamoDB"
  policy      = data.aws_iam_policy_document.terraform_state_permissions.json
}

# terraform apply: admin, only from main (after review and merge)
module "github_oidc_role_terraform" {
  source              = "./modules/github-oidc-role"
  role_name           = "github-actions-terraform-oidc-role"
  github_repos        = local.github_oidc_repos
  allowed_subjects    = ["ref:refs/heads/main"]
  oidc_provider_arn   = aws_iam_openid_connect_provider.github_core.arn
  ecr_repository_arns = []
  custom_policy_arns = [
    aws_iam_policy.terraform_state_policy.arn,
    "arn:aws:iam::aws:policy/AdministratorAccess"
  ]
}

# terraform plan on pull requests: read-only. ReadOnlyAccess can also read data in S3/DynamoDB; acceptable because
# GitHub does not issue OIDC tokens to pull requests from forks, so only collaborators with write access can assume it.
module "github_oidc_role_terraform_plan" {
  source              = "./modules/github-oidc-role"
  role_name           = "github-actions-terraform-plan-oidc-role"
  github_repos        = local.github_oidc_repos
  allowed_subjects    = ["pull_request"]
  oidc_provider_arn   = aws_iam_openid_connect_provider.github_core.arn
  ecr_repository_arns = []
  custom_policy_arns = [
    aws_iam_policy.terraform_state_read_policy.arn,
    "arn:aws:iam::aws:policy/ReadOnlyAccess"
  ]
}

#eks module configuration
module "eks" {
  source       = "./modules/eks"
  cluster_name = var.eks_cluster_name

  k8s_version = var.eks_k8s_version

  vpc_id = module.vpc.output_vpc_id

  vpc_config = local.eks_vpc_conf_finals

  capacity_type = var.eks_node_group_capacity_type

  instance_type = var.eks_node_group_instance_type

  ami_type = var.eks_node_group_ami_type

  disk_size = var.eks_node_group_disk_size

  node_scaling_config = var.eks_node_group_scaling_config

  cni_version = var.eks_cni_version

  coredns_version = var.eks_coredns_version

  kube_proxy_version = var.eks_kube_proxy_version

  depends_on = [module.vpc]
}

module "vpc_endpoints" {
  source              = "./modules/vpc-endpoints"
  region              = var.region
  vpc_id              = module.vpc.output_vpc_id
  vpc_cidr            = var.vpc_cidr
  private_subnet_list = module.vpc.private_subnet_ids
  route_table_list    = ["${module.vpc.private_subnet_route_table_id}"]

  depends_on = [module.vpc]
}
