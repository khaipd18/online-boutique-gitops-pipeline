variable "scan_on_push" {
  description = "Whether to enable basic scan on push for the repositories (registry-level scanning rule)"
  type        = bool
}

variable "image_tag_mutability" {
  description = "The tag mutability setting for the repository"
  type        = string
}

variable "force_delete" {
  description = "Whether to force delete the repository even if it contains images"
  type        = bool
}
variable "repository_names" {
  description = "The name of the ECR repository"
  type        = set(string)
}

variable "allow_push_principals" {
  description = "List of IAM principals allowed to push images to the repository"
  type        = list(string)
  default     = []
}

variable "allow_pull_principals" {
  description = "List of IAM principals allowed to pull images from the repository"
  type        = list(string)
  default     = []
}