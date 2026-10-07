variable "project" {
  description = "Name prefix for every resource"
  type        = string
  default     = "comfyui-gpu"
}

variable "aws_region" {
  description = "AWS region. us-east-1 has the widest G-family capacity"
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "Globally-unique S3 bucket for model artifacts, bootstrap files and outputs"
  type        = string
}

variable "instance_type" {
  description = "GPU instance type. g5.xlarge = NVIDIA A10G 24GB"
  type        = string
  default     = "g5.xlarge"
}

variable "purchase_option" {
  description = "on-demand or spot. Spot is cheaper but capacity is not guaranteed"
  type        = string
  default     = "on-demand"

  validation {
    condition     = contains(["on-demand", "spot"], var.purchase_option)
    error_message = "purchase_option must be on-demand or spot."
  }
}

variable "spot_max_price" {
  description = "Max USD/hour when purchase_option = spot"
  type        = string
  default     = "0.60"
}

variable "allowed_cidrs" {
  description = "Operator CIDRs (x.x.x.x/32) allowed to reach the UI and SSH. ComfyUI has no auth"
  type        = list(string)

  validation {
    condition     = length(var.allowed_cidrs) > 0 && alltrue([for c in var.allowed_cidrs : can(cidrnetmask(c))])
    error_message = "Provide at least one valid CIDR, e.g. 203.0.113.7/32."
  }
}

variable "key_name" {
  description = "Optional EC2 key pair for SSH. Leave empty to use SSM Session Manager only"
  type        = string
  default     = ""
}

variable "root_volume_gb" {
  description = "Root EBS size. Models live on instance-store NVMe, so this stays small"
  type        = number
  default     = 75
}

variable "notify_email" {
  description = "Recipient of budget alerts"
  type        = string
}

variable "ami_id" {
  description = "Manual AMI override. Empty = latest AWS Deep Learning AMI (Ubuntu 22.04)"
  type        = string
  default     = ""
}
