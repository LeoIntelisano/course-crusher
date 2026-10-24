import json;
import sys;
import from pathlib { Path }
import from tempfile { TemporaryDirectory }
import from unittest.mock { patch }
import from jaclang.byllm.lib { MockLLM }
import from breakdown { CognitiveTier, Subtask, break_down, extract_subtasks }

def sample -> dict[str, any] {
    return {
        "id": 1001, "course_id": 449, "name": " Project 2 ",
        "description": "<p>Write code.</p>", "due_at": "2026-11-06T23:59:00-05:00",
        "html_url": "https://canvas.example.edu/courses/449/assignments/1001"
    };
}

test "fixture maps source fields and normalizes dates without an API key" {
    drafts = load_assignment_fixture("fixtures/canvas/assignments.json");
    assert len(drafts) == 3;
    first = drafts[0];
    assert first.source_assignment_id == "1001" and first.source_course_id == "449";
    assert first.title == "Implement Linear Regression";
    assert first.description == "Implement gradient descent.\nCompare three learning rates.\nSubmit code and a two-page report.";
    assert first.due_at == "2026-11-07T04:59:00+00:00";
    assert first.source_url.endswith("/1001") and not first.needs_description;
    assert drafts[1].due_at == "";
    assert drafts[1].description == "Read Chapter 3 & summarize its main argument.";
    assert drafts[2].description == "" and drafts[2].needs_description;
}

test "HTML conversion preserves structure and decodes entities once" {
    assert assignment_text("<p>Read <strong>Chapter 3</strong> &amp; compare.</p><p>A<br>B</p>") == "Read Chapter 3 & compare.\nA\nB";
    assert assignment_text("<p>&lt;tag&gt; &amp;lt; &nbsp; done</p>") == "<tag> &lt; done";
    assert assignment_text("<table><tr><td>A</td></tr><tr><td>B</td></tr></table>") == "A\nB";
    assert assignment_text("<table><tr><td>Read</td><td>Chapter 3</td></tr></table>") == "Read Chapter 3";
}

test "HTML comments and executable text are not assignment instructions" {
    assert assignment_text("<!--hidden--><script>bad()</script><style>body{}</style><p>Write code.</p>") == "Write code.";
    assert assignment_text("<p>Unclosed <strong>markup") == "Unclosed markup";
}

test "missing optional fields stay empty and do not invent instructions" {
    draft = convert_assignment({"id": 1, "course_id": 2, "name": " Quiz "});
    assert draft.title == "Quiz";
    assert draft.description == "" and draft.needs_description;
    assert draft.due_at == "" and draft.source_url == "";
    raw = sample();
    raw["description"] = "<p> </p>";
    assert convert_assignment(raw).needs_description;
}

test "invalid IDs and blank titles are rejected" {
    for field in ["id", "course_id"] {
        for value in [None, True, 0, -1, "449"] {
            raw = sample();
            raw[field] = value;
            with testraises(ValueError, `match="positive integer") {
                convert_assignment(raw);
            }
        }
    }
    raw = sample();
    raw["name"] = "  ";
    with testraises(ValueError, `match="name cannot be empty") {
        convert_assignment(raw);
    }
}

test "wrong field types are rejected without coercion" {
    for field in ["name", "description", "due_at", "html_url"] {
        raw = sample();
        raw[field] = 123;
        with testraises(ValueError, `match="string or null") {
            convert_assignment(raw);
        }
    }
}

test "due dates require a timezone and preserve the instant across offsets" {
    for invalid in ["tomorrow", "2026-11-06", "2026-11-06T23:59:00"] {
        with testraises(ValueError, `match="timezone") {
            canvas_due_at(invalid);
        }
    }
    assert canvas_due_at("2026-11-07T04:59:00Z") == canvas_due_at("2026-11-06T23:59:00-05:00");
}

test "source links must be HTTPS without embedded credentials" {
    for url in ["javascript:alert(1)", "http://example.edu/x", "https:///x", "https://user:pass@example.edu/x"] {
        raw = sample();
        raw["html_url"] = url;
        with testraises(ValueError, `match="HTTPS") {
            convert_assignment(raw);
        }
    }
}

test "duplicate source identities are rejected and inputs are unchanged" {
    raw = sample();
    original = json.dumps(raw);
    with testraises(ValueError, `match="Duplicate Canvas") {
        convert_assignments([raw, raw]);
    }
    assert json.dumps(raw) == original;
    other = sample();
    other["course_id"] = 450;
    assert len(convert_assignments([raw, other])) == 2;
}

test "response page shape is checked and empty pages are allowed" {
    assert convert_assignments([]) == [];
    with testraises(ValueError, `match="must be an object") {
        convert_assignments(["not an assignment"]);
    }
    with TemporaryDirectory() as tmp {
        path = Path(tmp) / "invalid.json";
        path.write_text("{}", encoding="utf-8");
        with testraises(ValueError, `match="JSON array") {
            load_assignment_fixture(str(path));
        }
    }
}

test "preview JSON round trips the normalized fields" {
    drafts = [convert_assignment(sample())];
    preview = json.loads(preview_json(drafts));
    assert preview[0]["description"] == "Write code.";
    assert preview[0]["needs_description"] is False;
    assert preview[0]["source_course_id"] == "449";
}

test "converted text feeds the existing breakdown pipeline without calling a provider" {
    draft = load_assignment_fixture("fixtures/canvas/assignments.json")[0];
    model = MockLLM(outputs=[[
        Subtask(subtask_id="raw", title="Implement gradient descent", tier=CognitiveTier.DEEP_WORK, estimated_duration=50, order=9)
    ]]);
    with patch.object(sys.modules[extract_subtasks.__module__], "llm", model, create=True) {
        subtasks = break_down(draft.description);
    }
    assert subtasks[0].subtask_id == "subtask-1" and subtasks[0].order == 1;
    assert subtasks[0].tier == CognitiveTier.DEEP_WORK;
    messages = str(model.sent("messages"));
    assert "Compare three learning rates." in messages;
    assert "Submit code and a two-page report." in messages;
    assert "<li>" not in messages;
}
