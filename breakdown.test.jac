import json;
import sys;
import from contextlib { redirect_stderr }
import from io { StringIO }
import from pathlib { Path }
import from tempfile { TemporaryDirectory }
import from datetime { datetime, timedelta, timezone }
import from unittest.mock { patch }
import from jaclang.byllm.lib { MockLLM }

glob ASSIGNMENTS: Path = Path("fixtures/assignments");
glob ALLOWED_TIERS: set[str] = {"Deep Work", "Shallow Work", "Low Energy"};

def assignment(name: str) -> str {
    return (ASSIGNMENTS / f"{name}.txt").read_text(encoding="utf-8");
}

def step(title: str, tier: CognitiveTier, minutes: int, order: int = 0, subtask_id: str = "") -> Subtask {
    return Subtask(
        subtask_id=subtask_id, title=title, tier=tier, estimated_duration=minutes, order=order
    );
}

"""Spawn the walker with `model` standing in for the configured LLM."""
def run_breakdown(model: MockLLM, text: str) -> list[Subtask] {
    with patch.object(sys.modules[extract_subtasks.__module__], "llm", model, create=True) {
        run = root spawn BreakdownAssignment(assignment_text=text);
    }
    assert len(run.reports) == 1, f"expected one report, got {len(run.reports)}";
    return run.reports[0];
}

def assert_contract(subtasks: list[Subtask]) {
    assert subtasks, "breakdown is empty";
    assert len({s.subtask_id for s in subtasks}) == len(subtasks), "subtask IDs are not unique";
    assert [s.order for s in subtasks] == list(range(1, len(subtasks) + 1));
    for s in subtasks {
        assert s.title and s.title == s.title.strip(), f"bad title {s.title!r}";
        assert s.tier in ALLOWED_TIERS, f"bad tier {s.tier!r}";
        assert isinstance(s.estimated_duration, int) and s.estimated_duration > 0;
    }
}

test "coding assignment breaks down into ordered, typed subtasks" {
    model = MockLLM(outputs=[[
        step("Implement compute_loss and compute_gradient", CognitiveTier.DEEP_WORK, 60, 1, "a"),
        step("Implement gradient_descent and run all three learning rates", CognitiveTier.DEEP_WORK, 75, 2, "a"),
        step("Plot loss against iteration for each rate", CognitiveTier.SHALLOW_WORK, 30, 3, "b"),
        step("Write the one-page results and learning-rate explanation", CognitiveTier.DEEP_WORK, 45, 4, "c"),
        step("Submit project2.py and writeup.pdf to Gradescope", CognitiveTier.LOW_ENERGY, 10, 5, "d")
    ]]);

    subtasks = run_breakdown(model, assignment("coding_linear_regression"));

    assert_contract(subtasks);
    assert [s.subtask_id for s in subtasks] == [f"subtask-{n}" for n in range(1, 6)];
    assert subtasks[0].title == "Implement compute_loss and compute_gradient";
    assert subtasks[-1].tier == CognitiveTier.LOW_ENERGY;
}

test "writing assignment output is renumbered in returned order" {
    model = MockLLM(outputs=[[
        step("Draft the introduction and method sections", CognitiveTier.DEEP_WORK, 50, 3),
        step("Build the period table and fit the amplitude decay", CognitiveTier.DEEP_WORK, 60, 3),
        step("Write the discussion comparing damping to the lab manual", CognitiveTier.DEEP_WORK, 45, 9),
        step("Format citations and export the report to PDF", CognitiveTier.SHALLOW_WORK, 20, 0)
    ]]);

    subtasks = run_breakdown(model, assignment("writing_lab_report"));

    assert_contract(subtasks);
    assert [s.title for s in subtasks][1] == "Build the period table and fit the amplitude decay";
}

test "mixed assignment keeps every tier and trims titles" {
    model = MockLLM(outputs=[[
        step("  Email the GSI the group's algorithm choice  ", CognitiveTier.LOW_ENERGY, 5),
        step("Read the Chapter 9 section and the assigned paper", CognitiveTier.DEEP_WORK, 80),
        step("Prove the approximation ratio for the slides", CognitiveTier.DEEP_WORK, 60),
        step("Build 8 to 10 slides with a worked example", CognitiveTier.SHALLOW_WORK, 70),
        step("Rehearse the full presentation with the group", CognitiveTier.SHALLOW_WORK, 30),
        step("Submit the individual reflection on Canvas", CognitiveTier.LOW_ENERGY, 15)
    ]]);

    subtasks = run_breakdown(model, assignment("mixed_research_presentation"));

    assert_contract(subtasks);
    assert subtasks[0].title == "Email the GSI the group's algorithm choice";
    assert {str(s.tier) for s in subtasks} == ALLOWED_TIERS;
}

test "the assignment description is sent to the model" {
    model = MockLLM(outputs=[[step("Plot loss against iteration", CognitiveTier.SHALLOW_WORK, 30)]]);
    text = assignment("coding_linear_regression");

    run_breakdown(model, text);

    assert "housing.csv" in str(model.sent("messages"));
}

test "a single actionable task yields one subtask" {
    model = MockLLM(outputs=[[step("Submit the signed syllabus quiz on Canvas", CognitiveTier.LOW_ENERGY, 5)]]);

    subtasks = run_breakdown(model, "Submit the signed syllabus quiz on Canvas.");

    assert_contract(subtasks);
    assert len(subtasks) == 1;
}

test "empty input is rejected before calling the model" {
    for text in ["", "   \n\t"] {
        model = MockLLM(outputs=[]);
        with testraises(ValueError, `match="Assignment description cannot be empty") {
            run_breakdown(model, text);
        }
    }
}

test "an empty model response is rejected" {
    with testraises(ValueError, `match="no subtasks") {
        run_breakdown(MockLLM(outputs=[[]]), assignment("writing_lab_report"));
    }
}

test "a blank subtask title is rejected" {
    model = MockLLM(outputs=[[step("   ", CognitiveTier.SHALLOW_WORK, 20)]]);
    with testraises(ValueError, `match="title cannot be empty") {
        run_breakdown(model, assignment("writing_lab_report"));
    }
}

test "a non-positive duration is rejected" {
    for minutes in [0, -15] {
        model = MockLLM(outputs=[[step("Outline the report", CognitiveTier.SHALLOW_WORK, minutes)]]);
        with testraises(ValueError, `match="duration must be positive") {
            run_breakdown(model, assignment("writing_lab_report"));
        }
    }
}

test "normalize_subtasks returns new subtasks and leaves its input unchanged" {
    original = [
        step("  Outline the report  ", CognitiveTier.SHALLOW_WORK, 20, 7, "x"),
        step("Draft the discussion", CognitiveTier.DEEP_WORK, 45, 7, "x")
    ];

    normalized = normalize_subtasks(original);

    assert [(s.subtask_id, s.order, s.title) for s in original] == [
        ("x", 7, "  Outline the report  "), ("x", 7, "Draft the discussion")
    ];
    assert [(s.subtask_id, s.order, s.title) for s in normalized] == [
        ("subtask-1", 1, "Outline the report"), ("subtask-2", 2, "Draft the discussion")
    ];
}

def run_cli(model: MockLLM, argv: list[str]) -> tuple[int, str] {
    err = StringIO();
    with patch.object(sys.modules[extract_subtasks.__module__], "llm", model, create=True) {
        with redirect_stderr(err) {
            code = main(argv);
        }
    }
    return (code, err.getvalue());
}

test "the CLI rejects empty input with a message, not a traceback" {
    for argv in [[], ["  "]] {
        (code, err) = run_cli(MockLLM(outputs=[]), argv);
        assert code == 1;
        assert err.strip() == "breakdown: Assignment description cannot be empty.";
    }
}

test "the CLI reports invalid model output with a message" {
    model = MockLLM(outputs=[[step("Outline the report", CognitiveTier.SHALLOW_WORK, 0)]]);

    (code, err) = run_cli(model, ["Write", "the", "lab", "report"]);

    assert code == 1;
    assert err.strip() == "breakdown: A subtask duration must be positive.";
}

test "the CLI joins its arguments into one description and succeeds" {
    model = MockLLM(outputs=[[step("Submit the quiz", CognitiveTier.LOW_ENERGY, 5)]]);

    (code, err) = run_cli(model, ["Submit", "the", "quiz"]);

    assert code == 0, err;
    assert "Submit the quiz" in str(model.sent("messages"));
}

test "the CLI reports model failures with a message" {
    model = MockLLM(outputs=["not a subtask list"] * 5);

    (code, err) = run_cli(model, [assignment("writing_lab_report")]);

    assert code == 1;
    assert err.startswith("breakdown: The model call failed");
    assert "Traceback" not in err;
}

def run_endpoint(model: MockLLM, text: str) -> BreakdownResult {
    with patch.object(sys.modules[extract_subtasks.__module__], "llm", model, create=True) {
        return breakdown_result(text);
    }
}

test "the endpoint returns validated subtasks" {
    model = MockLLM(outputs=[[
        step("  Outline the report ", CognitiveTier.SHALLOW_WORK, 20, 4, "x"),
        step("Draft the discussion", CognitiveTier.DEEP_WORK, 45, 4, "x")
    ]]);

    result = run_endpoint(model, assignment("writing_lab_report"));

    assert result.ok and result.error == "";
    assert_contract(result.subtasks);
    assert result.subtasks[0].title == "Outline the report";
}

test "the endpoint explains empty and oversized input without calling the model" {
    model = MockLLM(outputs=[]);
    with patch.object(sys.modules[extract_subtasks.__module__], "llm", model, create=True) {
        empty = break_down_assignment("   ");
        oversized = break_down_assignment("x" * (MAX_ASSIGNMENT_CHARS + 1));
    }

    assert not empty.ok and empty.error == "Assignment description cannot be empty.";
    assert not oversized.ok and "at most" in oversized.error;
}

test "the endpoint reports invalid model output as a message" {
    result = run_endpoint(MockLLM(outputs=[[step("Outline", CognitiveTier.SHALLOW_WORK, 0)]]), "Write the report");

    assert not result.ok and result.error == "A subtask duration must be positive.";
}

test "the endpoint hides model failures behind a friendly message" {
    result = run_endpoint(MockLLM(outputs=["not a subtask list"] * 5), assignment("writing_lab_report"));

    assert not result.ok;
    assert result.error == "The AI breakdown isn't available right now. Try again in a minute.";
    assert "Traceback" not in result.error;
}

test "the fixture model answers every breakdown with canned steps" {
    module = sys.modules[extract_subtasks.__module__];
    had_override = hasattr(module, "llm");
    previous = getattr(module, "llm", None);
    with TemporaryDirectory() as tmp {
        fixture = Path(tmp) / "steps.json";
        fixture.write_text(json.dumps([
            {"title": "Read the brief", "tier": "Low Energy", "estimated_duration": 10},
            {"title": "Write the code", "tier": "Deep Work", "estimated_duration": 60}
        ]), encoding="utf-8");
        try {
            install_fixture_model(str(fixture));
            first = break_down("Anything at all");
            second = break_down("Something else");
        } finally {
            if had_override {
                setattr(module, "llm", previous);
            } else {
                delattr(module, "llm");
            }
        }
    }
    assert [(s.title, s.tier, s.estimated_duration) for s in first] == [
        ("Read the brief", CognitiveTier.LOW_ENERGY, 10), ("Write the code", CognitiveTier.DEEP_WORK, 60)
    ];
    assert [s.subtask_id for s in second] == ["subtask-1", "subtask-2"];
}

test "the hourly quota stops model calls past the limit" {
    usage = BreakdownUsage();
    start = datetime(2026, 10, 6, 12, 0, tzinfo=timezone.utc);

    allowed = [consume_quota(usage, start + timedelta(seconds=n)) for n in range(BREAKDOWNS_PER_HOUR)];
    refused = consume_quota(usage, start + timedelta(minutes=30));

    assert all(allowed) and not refused;
    assert usage.calls == BREAKDOWNS_PER_HOUR;
}

test "the quota resets after an hour" {
    usage = BreakdownUsage(window_start="2026-10-06T12:00:00+00:00", calls=BREAKDOWNS_PER_HOUR);

    assert consume_quota(usage, datetime(2026, 10, 6, 13, 0, 1, tzinfo=timezone.utc));
    assert usage.calls == 1;
}
