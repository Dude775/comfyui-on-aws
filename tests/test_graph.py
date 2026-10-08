import json
import pathlib
import random

import pytest

from comfy_pipeline.graph import (
    GraphError,
    inject,
    set_input_image,
)

EXAMPLE = pathlib.Path(__file__).parents[1] / "pipeline/workflows/qwen-edit-lightning.api.example.json"


@pytest.fixture
def graph():
    return json.loads(EXAMPLE.read_text())


def test_inject_fills_prompt_and_negative(graph):
    g = inject(graph, "make it night", "blurry", rng=random.Random(1))
    assert g["10"]["inputs"]["prompt"] == "make it night"
    assert g["11"]["inputs"]["prompt"] == "blurry"


def test_inject_does_not_mutate_input(graph):
    inject(graph, "x")
    assert graph["10"]["inputs"]["prompt"] == "{prompt}"


def test_inject_rolls_seed(graph):
    a = inject(graph, "x", rng=random.Random(1))["3"]["inputs"]["seed"]
    b = inject(graph, "x", rng=random.Random(2))["3"]["inputs"]["seed"]
    assert a != b


def test_inject_without_placeholder_fails_fast():
    with pytest.raises(GraphError):
        inject({"1": {"class_type": "CLIPTextEncode", "inputs": {"text": "hardcoded"}}}, "x")


def test_set_input_image(graph):
    assert set_input_image(graph, "a.png")["13"]["inputs"]["image"] == "a.png"


def test_set_input_image_requires_loadimage():
    with pytest.raises(GraphError):
        set_input_image({"1": {"class_type": "KSampler", "inputs": {}}}, "a.png")

