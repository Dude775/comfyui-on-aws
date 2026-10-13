# Runbook

## Start a session

```bash
make preflight            # identity is not root, quota >= 4 vCPU, current IP in SG
make plan && make apply   # first time only; later: aws ec2 start-instances
terraform -chdir=infra/terraform output comfy_url
```

On every boot `comfy-models.service` waits for the NVMe mount, re-syncs models from S3
(~3 min), then `comfyui.service` starts.

```bash
journalctl -u comfy-models -f   # model sync progress
journalctl -u comfyui -f        # server log
nvidia-smi                      # A10G should show ~22.5 GB total
```

## Run a batch

```bash
cd pipeline
python -m comfy_pipeline.cli --server http://<ip>:8188 \
  --workflow workflows/my-graph.json --prompts prompts.txt --quiet
```

`my-graph.json` and `prompts.txt` are git-ignored. Export the graph with
**Workflow -> Export (API)** and put `{prompt}` in the positive text node.

## Keep the node alive during a long manual session

```bash
sudo touch /var/lib/comfyui-watchdog/hold    # pause auto-shutdown
sudo rm -f /var/lib/comfyui-watchdog/hold    # resume
```

## End a session

```bash
make stop        # compute billing ends; EBS keeps code + outputs
make cost        # gross vs net month-to-date
```

## Decommission

```bash
make teardown                 # read-only inventory
make teardown ARGS=--apply    # typed confirmation, then delete
terraform -chdir=infra/terraform destroy
```

Order used in the real teardown: terminate instance -> wait for `terminated` -> empty
bucket -> delete bucket -> remove role from instance profile -> delete instance
profile -> detach managed policy -> delete inline policy -> delete role.

## Troubleshooting

| Symptom | First check |
|---|---|
| UI unreachable | home IP changed -> `make preflight` |
| ComfyUI crash-loop after start | `df -h /` - root full? NVMe race, see lessons #6 |
| Edits are copies of the input | `ModelSamplingAuraFlow.sampling` must be `flow` |
| Faces drift | sampler latent must come from `VAEEncode`, not `EmptyLatentImage` |
| Node stopped mid-work | watchdog saw 45 min idle - use the hold file |
