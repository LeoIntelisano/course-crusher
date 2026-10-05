"""Turn one assignment description into actionable subtasks."""

import sys;

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

def normalize_subtasks(subtasks: list[Subtask]) -> list[Subtask] {
    if not subtasks {
        raise ValueError("The assignment produced no subtasks.");
    }
    for index in range(len(subtasks)) {
        subtask = subtasks[index];
        subtask.title = subtask.title.strip();
        if not subtask.title {
            raise ValueError("A subtask title cannot be empty.");
        }
        if subtask.tier not in ["Deep Work", "Shallow Work", "Low Energy"] {
            raise ValueError(f"Invalid tier: {subtask.tier}");
        }
        if subtask.estimated_duration <= 0 {
            raise ValueError("A subtask duration must be positive.");
        }
        subtask.subtask_id = f"subtask-{index + 1}";
        subtask.order = index + 1;
    }
    return subtasks;
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

with entry:__main__ {
    assignment_text = " ".join(sys.argv[1:]);
    root spawn BreakdownAssignment(assignment_text=assignment_text);
}
