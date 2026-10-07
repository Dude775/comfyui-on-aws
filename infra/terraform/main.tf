# AWS Deep Learning AMI: NVIDIA driver + CUDA preinstalled, instance-store NVMe auto-mounted
data "aws_ami" "dlami" {
  count       = var.ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Deep Learning Base OSS Nvidia Driver GPU AMI (Ubuntu 22.04)*"]
  }
}

data "aws_vpc" "default" {
  default = true
}

locals {
  ami_id  = var.ami_id != "" ? var.ami_id : data.aws_ami.dlami[0].id
  is_spot = var.purchase_option == "spot"

  userdata = templatefile("${path.module}/../../bootstrap/userdata.sh.tpl", {
    bucket = var.bucket_name
    region = var.aws_region
  })
}
