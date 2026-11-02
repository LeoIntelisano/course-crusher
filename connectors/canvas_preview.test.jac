
test "sample dates use profile timezone" {
    drafts = sample_assignments("America/Detroit");
    assert drafts[0].due_at == "2026-11-06T23:59";
    assert "<" not in drafts[0].description;
    assert len(drafts) == 3;
}

test "missing sample fields stay empty" {
    drafts = sample_assignments("UTC");
    assert drafts[0].due_at == "2026-11-07T04:59";
    assert drafts[2].needs_description;
    assert drafts[2].description == "";
    assert drafts[2].due_at == "";
}
