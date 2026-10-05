resource "aws_security_group" "comfy" {
  name        = "${var.project}-sg"
  description = "ComfyUI UI and SSH from operator CIDRs only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "ComfyUI UI/API"
    from_port   = 8188
    to_port     = 8188
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  ingress {
    description = "SSH (break-glass, SSM preferred)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  egress {
    description = "Package mirrors, GitHub, S3"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
