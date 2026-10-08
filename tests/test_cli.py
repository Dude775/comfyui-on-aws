from comfy_pipeline.cli import read_prompts


def test_read_prompts_skips_comments_and_blanks(tmp_path):
    p = tmp_path / "p.txt"
    p.write_text("# header\n\nfirst\n  # indented comment\nsecond  \n", encoding="utf-8")
    assert read_prompts(p) == ["first", "second"]
