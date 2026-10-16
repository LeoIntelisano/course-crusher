"""Turn one assignment description into actionable subtasks."""

import json;
import logging;
import os;
import sys;
import from datetime { datetime, timedelta, timezone }
import from jaclang.byllm.lib { ByLLMError }

glob logger: logging.Logger = logging.getLogger("course_crusher.breakdown");
glob MAX_ASSIGNMENT_CHARS: int = 20000;
glob LLM_FIXTURE_ENV: str = "COURSE_CRUSHER_LLM_FIXTURE";
glob FIXTURE_REPEATS: int = 1000;
glob BREAKDOWNS_PER_HOUR: int = 30;
glob QUOTA_WINDOW: timedelta = timedelta(hours=1);

enum CognitiveTier: str {
    DEEP_WORK = "Deep Work",
    SHALLOW_WORK = "Shallow Work",
    LOW_ENERGY = "Low Energy"
}

sem CognitiveTier.DEEP_WORK = "Requires sustained focus, such as coding, difficult problem solving, analysis, or substantial drafting.";
sem CognitiveTier.SHALLOW_WORK = "Routine work that needs attention but little sustained concentration, such as formatting or multi-step administration.";
sem CognitiveTier.LOW_ENERGY = "A quick, straightforward action, such as a simple submission, light review, or short reading.";

obj Subtask {
    has subtask_id: str;
    has title: str;
    has tier: CognitiveTier;
    has estimated_duration: int;
    has order: int;
}

sem Subtask.subtask_id = "A unique ID within this breakdown, such as subtask-1.";
sem Subtask.title = "A specific action that begins with a verb.";
sem Subtask.tier = "Exactly Deep Work, Shallow Work, or Low Energy.";
sem Subtask.estimated_duration = "A realistic positive estimate in minutes for this action.";
sem Subtask.order = "The one-based execution sequence.";

def extract_subtasks(assignment_text: str) -> list[Subtask] by llm(
    temperature=0.2,
    system_prompt=
    """Break an assignment into concrete actions in execution order. 
    Each action should fit a 15 to 90 minute work session and have a visible outcome. 
    Split larger work into smaller actions supported by the assignment. 
    If the input is already one actionable task, return exactly one subtask that preserves that action.
    Do not add planning, review, breakdown, or presentation steps for a single task.
    Use Deep Work for coding, difficult problem solving, analysis, or substantial drafting. 
    Use Shallow Work for routine edits, formatting, or multi-step administration.
    Use Low Energy for a simple submission, light review, or straightforward reading; demanding reading is Deep Work.
    Estimate each action in minutes. Do not invent deliverables or requirements. 
    Return the actions in the suggested execution order."""
);
sem extract_subtasks = "Extract actionable subtasks from one assignment description.";
sem extract_subtasks.assignment_text = "The complete raw assignment description.";

"""Validate one model-produced subtask and return a clean copy at `position`."""
def normalize_subtask(subtask: Subtask, position: int) -> Subtask {
    title = subtask.title.strip();
    if not title {
        raise ValueError("A subtask title cannot be empty.");
    }
    if subtask.tier not in list(CognitiveTier) {
        raise ValueError(f"Invalid tier: {subtask.tier}");
    }
    if subtask.estimated_duration <= 0 {
        raise ValueError("A subtask duration must be positive.");
    }
    return Subtask(
        subtask_id=f"subtask-{position}",
        title=title,
        tier=CognitiveTier(subtask.tier),
        estimated_duration=subtask.estimated_duration,
        order=position
    );
}

"""Validate the model's subtasks and renumber IDs and order from 1, in returned order."""
def normalize_subtasks(subtasks: list[Subtask]) -> list[Subtask] {
    if not subtasks {
        raise ValueError("The assignment produced no subtasks.");
    }
    return [
        normalize_subtask(subtask, position)
        for (position, subtask) in enumerate(subtasks, start=1)
    ];
}

"""Reject empty input before calling the model, then validate what it returns."""
def break_down(assignment_text: str) -> list[Subtask] {
    if not assignment_text.strip() {
        raise ValueError("Assignment description cannot be empty.");
    }
    return normalize_subtasks(extract_subtasks(assignment_text));
}

walker BreakdownAssignment {
    has assignment_text: str;
    has reports: list[list[Subtask]] = [];

    can break_down_text with Root entry {
        report break_down(self.assignment_text);
    }
}

obj BreakdownResult {
    has ok: bool;
    has error: str = "";
    has subtasks: list[Subtask] = [];
}

"""Model calls a student made in the current hour. Each call costs money, and signup is open."""
node BreakdownUsage {
    has window_start: str = "";
    has calls: int = 0;
}

def ensure_usage -> BreakdownUsage {
    existing = [root-->[?:BreakdownUsage]];
    if existing {
        return existing[0];
    }
    return root ++> BreakdownUsage();
}

"""Count one model call. False once the student is over the hourly limit."""
def consume_quota(usage: BreakdownUsage, now: datetime) -> bool {
    started = datetime.fromisoformat(usage.window_start) if usage.window_start else None;
    if started is None or now - started >= QUOTA_WINDOW {
        usage.window_start = now.isoformat();
        usage.calls = 0;
    }
    if usage.calls >= BREAKDOWNS_PER_HOUR {
        return False;
    }
    usage.calls += 1;
    return True;
}

"""The Breakdown screen's call. Model and validation failures come back as a message, not a 500."""
def:protect break_down_assignment(assignment_text: str) -> BreakdownResult {
    if len(assignment_text) > MAX_ASSIGNMENT_CHARS {
        return BreakdownResult(
            ok=False, error=f"Paste at most {MAX_ASSIGNMENT_CHARS} characters of the assignment."
        );
    }
    if not assignment_text.strip() {
        return BreakdownResult(ok=False, error="Assignment description cannot be empty.");
    }
    if not consume_quota(ensure_usage(), datetime.now(timezone.utc)) {
        return BreakdownResult(
            ok=False,
            error=f"You've run {BREAKDOWNS_PER_HOUR} breakdowns this hour. Try again later."
        );
    }
    return breakdown_result(assignment_text);
}

"""Run the breakdown and turn validation or model failures into a message."""
def breakdown_result(assignment_text: str) -> BreakdownResult {
    try {
        return BreakdownResult(ok=True, subtasks=break_down(assignment_text));
    } except ValueError as err {
        return BreakdownResult(ok=False, error=str(err));
    } except ByLLMError as err {
        logger.error("Breakdown model call failed: %s", err);
        return BreakdownResult(
            ok=False, error="The AI breakdown isn't available right now. Try again in a minute."
        );
    }
}

"""Answer every breakdown from a JSON fixture instead of a real model.

For end-to-end runs without an API key only. The fixture is a list of
{"title", "tier", "estimated_duration"} objects.
"""
def install_fixture_model(path: str) {
    import from jaclang.byllm.lib { MockLLM }
    with open(path, encoding="utf-8") as handle {
        steps = json.load(handle);
    }
    canned = [
        Subtask(
            subtask_id=f"subtask-{n}",
            title=step["title"],
            tier=CognitiveTier(step["tier"]),
            estimated_duration=int(step["estimated_duration"]),
            order=n
        )
        for (n, step) in enumerate(steps, start=1)
    ];
    setattr(sys.modules[extract_subtasks.__module__], "llm", MockLLM(outputs=[canned] * FIXTURE_REPEATS));
    logger.warning("%s is set: breakdowns use canned output from %s", LLM_FIXTURE_ENV, path);
}

with entry {
    if os.environ.get(LLM_FIXTURE_ENV) {
        install_fixture_model(os.environ[LLM_FIXTURE_ENV]);
    }
}

"""Break down the description in `argv`; `jac run` prints the walker's report."""
def main(argv: list[str]) -> int {
    try {
        root spawn BreakdownAssignment(assignment_text=" ".join(argv));
    } except ValueError as err {
        print(f"breakdown: {err}", file=sys.stderr);
        return 1;
    } except ByLLMError as err {
        print(f"breakdown: The model call failed: {err}", file=sys.stderr);
        return 1;
    }
    return 0;
}

with entry:__main__ {
    sys.`exit(main(sys.argv[1:]));
}
