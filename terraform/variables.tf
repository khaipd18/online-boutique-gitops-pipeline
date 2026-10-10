# Variables for Terraform configuration
variable "region" {
  description = "The AWS region to deploy resources in"
  default     = "ap-southeast-1"
}
#vpc configuration
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.18.0.0/16"
}

variable "az_ids" {
  type        = list(string)
  description = "List of availability zone IDs for subnets"
  default     = ["apse1-az1", "apse1-az2"]
}

#ecr configuration
variable "scan_on_push" {
  description = "Whether to enable basic scan on push for the repositories (registry-level scanning rule)"
  type        = bool
  default     = true
}

variable "repository_names" {
  description = "List of ECR repository names"
  type        = set(string)
  default = ["shippingservice", "recommendationservice", "productcatalogservice",
  "paymentservice", "frontend", "emailservice", "currencyservice", "checkoutservice", "cartservice", "adservice"]
}

variable "force_delete" {
  description = "Whether to force delete the repository even if it contains images"
  type        = bool
  default     = true
}

variable "image_tag_mutability" {
  description = "The tag mutability setting for the repository. CI tags images with the git SHA, so tags never need to be overwritten"
  type        = string
  default     = "IMMUTABLE"
}

variable "allow_push_principals" {
  description = "List of principals allowed to push images to the repository"
  type        = list(string)
  default     = []
}

variable "allow_pull_principals" {
  description = "List of principals allowed to pull images from the repository"
  type        = list(string)
  default     = []
}

# Terraform state backend: these must match the values in backend.tf (backend blocks cannot use variables)
variable "tf_state_bucket" {
  description = "Name of the S3 bucket holding the Terraform state"
  type        = string
  default     = "khaipd18-obe-tf-state-445817183958"
}

variable "tf_state_lock_table" {
  description = "Name of the DynamoDB table used for Terraform state locking"
  type        = string
  default     = "khaipd18-devops-project-terraform-state-lock"
}

variable "github_repo" {
  description = "The GitHub repository in the format 'owner/repo' that will be allowed to assume the role"
  type        = string
  default     = "khaipd18/online-boutique-gitops-pipeline"
}

# GitHub uses an immutable sub format (owner@<owner-id>/repo@<repo-id>) for repositories created, renamed or
# transferred after 2026-07-15. This repo was renamed, so both formats are trusted. Set to "" to trust only github_repo.
variable "github_repo_immutable" {
  description = "The GitHub repository in the immutable OIDC sub format 'owner@owner_id/repo@repo_id'"
  type        = string
  default     = "khaipd18@174919444/online-boutique-gitops-pipeline@1204916149"
}

#eks configuration
# EKS cluster variables
variable "eks_cluster_name" {
  description = "The name of the EKS cluster."
  type        = string
  default     = "khaipd18-eks-cluster"
}

variable "eks_vpc_config_override" {
  type = object({
    endpoint_private_access = optional(bool)
    endpoint_public_access  = optional(bool)
    public_access_cidrs     = optional(list(string))
  })
  description = "Override for the default VPC configuration of the EKS cluster. Only include fields that need to be overridden."
  default = {
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"]
  }
}

variable "eks_k8s_version" {
  description = "The Kubernetes version to use for the EKS cluster."
  type        = string
  default     = "1.35"
}

#eks node group variables
variable "eks_node_group_instance_type" {
  description = "The EC2 instance type to use for the EKS node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "eks_node_group_ami_type" {
  description = "The AMI type to use for the EKS node group."
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "eks_node_group_capacity_type" {
  description = "The capacity type to use for the EKS node group (e.g., ON_DEMAND or SPOT)."
  type        = string
  default     = "ON_DEMAND"
}

variable "eks_node_group_disk_size" {
  description = "The disk size (in GiB) to use for the EKS node group."
  type        = number
  default     = 20
}

variable "eks_node_group_scaling_config" {
  description = "The scaling configuration for the EKS node group."
  type = object({
    desired_size = number
    max_size     = number
    min_size     = number
  })
  default = {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }
}

#eks addon variables
variable "eks_cni_version" {
  description = "The version of the VPC CNI plugin to use for the EKS cluster."
  type        = string
  default     = "v1.21.1-eksbuild.7"
}

variable "eks_coredns_version" {
  description = "The version of the CoreDNS addon to use for the EKS cluster."
  type        = string
  default     = "v1.13.2-eksbuild.4"
}

variable "eks_kube_proxy_version" {
  description = "The version of the kube-proxy addon to use for the EKS cluster."
  type        = string
  default     = "v1.35.3-eksbuild.2"
}

variable "eks_metrics_server_version" {
  description = "The version of the Metrics Server community addon to use for the EKS cluster."
  type        = string
  default     = "v0.9.0-eksbuild.11"
}

