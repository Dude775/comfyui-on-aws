"""Batch runner: prompts file -> remote ComfyUI node -> local ./out folder.

Prompts and images stay on the operator machine. Nothing is logged except
truncated progress lines, and --quiet hides even those.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

from .client import ComfyClient
from .graph import GraphError, inject


def read_prompts(path: pathlib.Path) -> list[str]:
    return [
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="comfy-batch")
    ap.add_argument("--server", required=True, help="http://<node-ip>:8188")
    ap.add_argument("--workflow", required=True, type=pathlib.Path, help="API-format graph with {prompt}")
    ap.add_argument("--prompts", required=True, type=pathlib.Path, help="one prompt per line")
    ap.add_argument("--negative", default=None)
    ap.add_argument("--out", default="out", type=pathlib.Path)
    ap.add_argument("--quiet", action="store_true", help="never echo prompt text")
    a = ap.parse_args(argv)

    client = ComfyClient(a.server)
    try:
        stats = client.health()
    except OSError as e:
        print(f"[fail] node unreachable at {a.server}: {e}", file=sys.stderr)
        return 2
    dev = (stats.get("devices") or [{}])[0]
    print(f"[ok] node up: {dev.get('name', '?')} vram_total={dev.get('vram_total', '?')}")

    graph = json.loads(a.workflow.read_text(encoding="utf-8"))
    prompts = read_prompts(a.prompts)
    a.out.mkdir(exist_ok=True)

    done = 0
    for i, p in enumerate(prompts, 1):
        label = f"#{i}" if a.quiet else p[:50]
        try:
            pid = client.submit(inject(graph, p, a.negative))
        except GraphError as e:
            print(f"[fail] {e}", file=sys.stderr)
            return 1
        outputs = client.wait(pid)
        if outputs is None:
            print(f"[{i}/{len(prompts)}] timeout {label}")
            continue
        saved = client.download_outputs(outputs, a.out, f"{i:03d}")
        print(f"[{i}/{len(prompts)}] ok {label} -> {len(saved)} file(s)")
        done += 1
    print(f"[done] {done}/{len(prompts)} -> {a.out}/")
    return 0 if done == len(prompts) else 1


if __name__ == "__main__":
    raise SystemExit(main())
