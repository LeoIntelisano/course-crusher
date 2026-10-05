"""Turn one assignment description into actionable subtasks."""

import sys;
import from jaclang.byllm.lib { ByLLMError }

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

walker BreakdownAssignment {
    has assignment_text: str;
    has reports: list[list[Subtask]] = [];

    can break_down with Root entry {
        if not self.assignment_text.strip() {
            raise ValueError("Assignment description cannot be empty.");
        }
        report normalize_subtasks(extract_subtasks(self.assignment_text));
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
