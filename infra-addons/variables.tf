variable "env" {
  type        = string
  description = "Environment name"
}

variable "vpc_name" {
  type        = string
  description = "VPC name"
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name"
}

variable "azs" {
  type        = list(string)
  description = "Availability zones"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block"
}

variable "private_subnets_cidr" {
  type        = list(string)
  description = "Private subnet CIDRs"
}

variable "public_subnets_cidr" {
  type        = list(string)
  description = "Public subnet CIDRs"
}

variable "eks_version" {
  type        = string
  description = "EKS version"
}

variable "admin_arn" {
  type        = string
  description = "ARN of the admin IAM user"
}

variable "principal_arn" {
  type        = string
  description = "ARN of the pipeline IAM role"
}

variable "principal_arn_name" {
  type        = string
  description = "Name for the principal ARN"
  default     = "admin"
}

variable "node_groups" {
  type = map(object({
    instance_types = list(string)
    capacity_type  = string
    scaling_config = object({
      desired_size = number
      max_size     = number
      min_size     = number
    })
  }))
  description = "EKS node groups"
  default     = {}
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace for the app"
  default     = "expense-tracker"
}

variable "repo_url" {
  type        = string
  description = "GitHub repo URL for ArgoCD to watch"
  default     = "https://github.com/Edwin-Oghenetejiri1/expense-tracker-k8s-manifests"
}

variable "repo_project" {
  type        = string
  description = "ArgoCD project name"
  default     = "default"
}

# MongoDB variables — stored in Secrets Manager, never in git
variable "mongo_username" {
  type        = string
  sensitive   = true
  description = "MongoDB root username"
}

variable "mongo_password" {
  type        = string
  sensitive   = true
  description = "MongoDB root password"
}

variable "mongo_db_name" {
  type        = string
  description = "MongoDB database name"
  default     = "expensedb"
}