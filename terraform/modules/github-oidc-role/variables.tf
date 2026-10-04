variable "role_name" {
  description = "The name of the IAM role to create for GitHub OIDC authentication"
  type        = string
}

variable "github_repos" {
  description = "The GitHub repository as it appears in the OIDC sub claim: 'owner/repo' and/or the immutable 'owner@id/repo@id' format"
  type        = list(string)
}

variable "allowed_subjects" {
  description = "The parts of the sub claim allowed after 'repo:<repo>:', e.g. 'ref:refs/heads/main' or 'pull_request'"
  type        = list(string)
}

variable "oidc_provider_arn" {
  description = "The ARN of the OIDC provider for GitHub in AWS IAM"
  type        = string
}

variable "ecr_repository_arns" {
  description = "A list of ECR repository ARNs that the role will have permissions to access"
  type        = list(string)
}

variable "custom_policy_arns" {
  description = "A list of additional IAM policy ARNs to attach to the role for extra permissions beyond ECR access"
  type        = list(string)
  default     = []
}