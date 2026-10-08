"""Pure functions that mutate an exported ComfyUI API graph. No I/O - fully unit-tested."""

from __future__ import annotations

import copy
import random

PROMPT_TOKEN = "{prompt}"
NEGATIVE_TOKEN = "{negative}"


class GraphError(ValueError):
    pass


def inject(graph: dict, prompt: str, negative: str | None = None, rng: random.Random | None = None) -> dict:
    """Return a copy of `graph` with the prompt placeholders filled and sampler seeds rolled.

    Raises GraphError if the graph has no {prompt} placeholder - catching an un-templated
    export before it burns GPU time.
    """
    rng = rng or random.Random()
    g = copy.deepcopy(graph)
    hits = 0
    for node in g.values():
        inputs = node.get("inputs", {})
        for key, val in list(inputs.items()):
            if not isinstance(val, str):
                continue
            if PROMPT_TOKEN in val:
                inputs[key] = val.replace(PROMPT_TOKEN, prompt)
                hits += 1
            elif NEGATIVE_TOKEN in val:
                inputs[key] = val.replace(NEGATIVE_TOKEN, negative or "")
        if "KSampler" in node.get("class_type", "") and isinstance(inputs.get("seed"), int):
            inputs["seed"] = rng.randint(0, 2**53)
    if hits == 0:
        raise GraphError("no {prompt} placeholder in graph - re-export with 'Export (API)'")
    return g


def set_input_image(graph: dict, filename: str) -> dict:
    g = copy.deepcopy(graph)
    found = False
    for node in g.values():
        if node.get("class_type") == "LoadImage":
            node.setdefault("inputs", {})["image"] = filename
            found = True
    if not found:
        raise GraphError("graph has no LoadImage node")
    return g


def sampler_settings(graph: dict) -> list[dict]:
    """Extract sampler config - used by CI to lint the committed example workflow."""
    out = []
    for node in graph.values():
        if "KSampler" in node.get("class_type", ""):
            i = node.get("inputs", {})
            out.append({k: i.get(k) for k in ("steps", "cfg", "sampler_name", "scheduler", "denoise")})
    return out


def latent_source(graph: dict) -> str | None:
    """Class type feeding the sampler's latent_image. EmptyLatentImage in an EDIT graph
    means the source image is ignored - the 'faces drift' bug."""
    for node in graph.values():
        if "KSampler" in node.get("class_type", ""):
            ref = node.get("inputs", {}).get("latent_image")
            if isinstance(ref, list) and ref:
                return graph.get(str(ref[0]), {}).get("class_type")
    return None
