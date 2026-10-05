output "comfy_url" {
  description = "ComfyUI in the browser (reachable from allowed_cidrs only)"
  value       = "http://${aws_instance.comfy.public_ip}:8188"
}

output "instance_id" {
  value = aws_instance.comfy.id
}

output "ssm_session" {
  description = "Shell on the node without SSH keys"
  value       = "aws ssm start-session --region ${var.aws_region} --target ${aws_instance.comfy.id}"
}

output "stop_command" {
  description = "Stop billing for compute (EBS keeps outputs)"
  value       = "aws ec2 stop-instances --region ${var.aws_region} --instance-ids ${aws_instance.comfy.id}"
}
