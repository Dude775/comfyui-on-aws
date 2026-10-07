resource "aws_instance" "comfy" {
  ami                    = local.ami_id
  instance_type          = var.instance_type
  iam_instance_profile   = aws_iam_instance_profile.instance.name
  vpc_security_group_ids = [aws_security_group.comfy.id]
  key_name               = var.key_name != "" ? var.key_name : null
  user_data_base64       = base64gzip(local.userdata)

  # On-demand: stop keeps the EBS disk (outputs survive). Spot one-time can only terminate.
  instance_initiated_shutdown_behavior = local.is_spot ? "terminate" : "stop"

  dynamic "instance_market_options" {
    for_each = local.is_spot ? [1] : []
    content {
      market_type = "spot"
      spot_options {
        max_price                      = var.spot_max_price
        spot_instance_type             = "one-time"
        instance_interruption_behavior = "terminate"
      }
    }
  }

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }

  root_block_device {
    volume_size           = var.root_volume_gb
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = { Name = "${var.project}-node" }
}
