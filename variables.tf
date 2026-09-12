# -----------------------------------------------------
# Required
# -----------------------------------------------------

variable "app_name" {
  description = "Application name, used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g. dev, staging, prod)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the EKS cluster will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the EKS cluster and node groups"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for load balancers"
  type        = list(string)
}

variable "eks_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.34"
}

variable "cluster_admin_arns" {
  description = "List of IAM role/user ARNs to grant EKS cluster admin access"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------
# Node group defaults
# -----------------------------------------------------

variable "node_group_instance_types" {
  description = "Instance types for the managed node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "capacity_type" {
  description = "Capacity type for the managed node group (ON_DEMAND or SPOT)"
  type        = string
  default     = "ON_DEMAND"
}

variable "ami_type" {
  description = "AMI type for the managed node group"
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "desired_size" {
  description = "Desired number of nodes in the managed node group"
  type        = number
  default     = 2
}

variable "min_size" {
  description = "Minimum number of nodes in the managed node group"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of nodes in the managed node group"
  type        = number
  default     = 4
}

# -----------------------------------------------------
# Feature flags
# -----------------------------------------------------

variable "deploy_ebs_csi" {
  description = "Deploy the EBS CSI driver addon with Pod Identity"
  type        = bool
  default     = true
}

variable "deploy_karpenter" {
  description = "Deploy Karpenter for autoscaling with Pod Identity"
  type        = bool
  default     = false
}

# -----------------------------------------------------
# Addon version overrides
# -----------------------------------------------------

variable "vpc_cni_version" {
  description = "Version of the VPC CNI addon"
  type        = string
  default     = "v1.23.1-eksbuild.1"
}

variable "kube_proxy_version" {
  description = "Version of the kube-proxy addon"
  type        = string
  default     = "v1.34.6-eksbuild.25"
}

variable "coredns_version" {
  description = "Version of the CoreDNS addon"
  type        = string
  default     = "v1.13.2-eksbuild.24"
}

variable "pod_identity_agent_version" {
  description = "Version of the EKS Pod Identity Agent addon"
  type        = string
  default     = "v1.4.0-eksbuild.2"
}

variable "ebs_csi_version" {
  description = "Version of the EBS CSI driver addon"
  type        = string
  default     = "v1.65.0-eksbuild.2"
}

variable "karpenter_version" {
  description = "Karpenter Helm chart version (must be compatible with eks_version — see research/karpenter-pod-identity.md)"
  type        = string
  default     = "1.1.1"
}
