# EKS cluster variables
variable "cluster_name" {
  description = "The name of the EKS cluster."
  type        = string
}

variable "log_retention_days" {
  description = "Number of days to keep the control plane logs in CloudWatch Logs."
  type        = number
}

variable "vpc_id" {
  description = "The ID of the VPC where the EKS cluster will be created."
  type        = string
}

variable "vpc_config" {
  type = object({
    subnet_ids              = list(string)
    endpoint_private_access = bool
    endpoint_public_access  = bool
    public_access_cidrs     = list(string)
  })
}

variable "k8s_version" {
  description = "The Kubernetes version to use for the EKS cluster."
  type        = string
}

#eks node group variables
variable "instance_type" {
  description = "The EC2 instance type to use for the EKS node group."
  type        = list(string)
}

variable "ami_type" {
  description = "The AMI type to use for the EKS node group."
  type        = string
}

variable "capacity_type" {
  description = "The capacity type to use for the EKS node group (e.g., ON_DEMAND or SPOT)."
  type        = string
}

variable "disk_size" {
  description = "The disk size (in GiB) to use for the EKS node group."
  type        = number
}

variable "node_scaling_config" {
  description = "The scaling configuration for the EKS node group."
  type = object({
    desired_size = number
    max_size     = number
    min_size     = number
  })
}

#eks addon variables
variable "cni_version" {
  description = "The version of the VPC CNI plugin to use for the EKS cluster."
  type        = string
}

variable "coredns_version" {
  description = "The version of the CoreDNS addon to use for the EKS cluster."
  type        = string
}

variable "kube_proxy_version" {
  description = "The version of the kube-proxy addon to use for the EKS cluster."
  type        = string
}

variable "metrics_server_version" {
  description = "The version of the Metrics Server community addon to use for the EKS cluster."
  type        = string
}

