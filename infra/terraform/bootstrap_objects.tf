# Ship the watchdog + boot scripts through S3 so user-data stays tiny (16 KB limit)
locals {
  bootstrap_files = {
    "watchdog/comfyui-watchdog.sh"      = "${path.module}/../../ops/watchdog/comfyui-watchdog.sh"
    "watchdog/comfyui-watchdog.env"     = "${path.module}/../../ops/watchdog/comfyui-watchdog.env"
    "watchdog/comfyui-watchdog.service" = "${path.module}/../../ops/watchdog/comfyui-watchdog.service"
    "watchdog/comfyui-watchdog.timer"   = "${path.module}/../../ops/watchdog/comfyui-watchdog.timer"
    "watchdog/install.sh"               = "${path.module}/../../ops/watchdog/install.sh"
    "sync-models.sh"                    = "${path.module}/../../bootstrap/sync-models.sh"
    "systemd/comfyui.service"           = "${path.module}/../../bootstrap/systemd/comfyui.service"
    "systemd/comfy-models.service"      = "${path.module}/../../bootstrap/systemd/comfy-models.service"
  }
}

resource "aws_s3_object" "bootstrap" {
  for_each = local.bootstrap_files

  bucket = aws_s3_bucket.artifacts.id
  key    = "bootstrap/${each.key}"
  source = each.value
  etag   = filemd5(each.value)
}
