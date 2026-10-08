"""Minimal ComfyUI HTTP API client - stdlib only, so it runs on any operator laptop."""

from __future__ import annotations

import json
import pathlib
import time
import urllib.parse
import urllib.request


class ComfyClient:
    def __init__(self, server: str, timeout: int = 30) -> None:
        self.server = server.rstrip("/")
        self.timeout = timeout

    def _json(self, path: str, payload: dict | None = None, timeout: int | None = None) -> dict:
        data = json.dumps(payload).encode() if payload is not None else None
        req = urllib.request.Request(self.server + path, data=data, method="POST" if data else "GET")
        req.add_header("Content-Type", "application/json")
        with urllib.request.urlopen(req, timeout=timeout or self.timeout) as r:
            return json.loads(r.read().decode())

    def health(self) -> dict:
        """GET /system_stats - proves the node is up and reports GPU/VRAM."""
        return self._json("/system_stats")

    def queue_depth(self) -> int:
        q = self._json("/queue")
        return len(q.get("queue_running", [])) + len(q.get("queue_pending", []))

    def submit(self, graph: dict) -> str:
        return self._json("/prompt", {"prompt": graph})["prompt_id"]

    def wait(self, prompt_id: str, poll_sec: float = 3.0, max_wait_sec: int = 600) -> dict | None:
        deadline = time.monotonic() + max_wait_sec
        while time.monotonic() < deadline:
            time.sleep(poll_sec)
            h = self._json(f"/history/{prompt_id}", timeout=10)
            if prompt_id in h and h[prompt_id].get("outputs"):
                return h[prompt_id]["outputs"]
        return None

    def download_outputs(self, outputs: dict, outdir: pathlib.Path, prefix: str) -> list[str]:
        saved = []
        for node_out in outputs.values():
            for img in node_out.get("images", []):
                q = urllib.parse.urlencode(img)
                name = f"{prefix}_{img['filename']}"
                urllib.request.urlretrieve(f"{self.server}/view?{q}", outdir / name)
                saved.append(name)
        return saved

    def upload_image(self, path: pathlib.Path) -> str:
        boundary = "----comfypipeline"
        body = (
            f'--{boundary}\r\nContent-Disposition: form-data; name="image"; '
            f'filename="{path.name}"\r\nContent-Type: image/png\r\n\r\n'
        ).encode() + path.read_bytes() + f"\r\n--{boundary}--\r\n".encode()
        req = urllib.request.Request(self.server + "/upload/image", data=body, method="POST")
        req.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")
        with urllib.request.urlopen(req, timeout=120) as r:
            resp = json.loads(r.read().decode())
        sub = resp.get("subfolder") or ""
        return f"{sub}/{resp['name']}" if sub else resp["name"]
