"""Sample Canvas drafts in the student's timezone."""
import from datetime { datetime }
import from account.schema { ensure_profile }
import from connectors.canvas_assignments { CanvasAssignmentDraft, load_assignment_fixture }
import from shared.timefmt { parse_zone }

def sample_assignments(zone: str) -> list[CanvasAssignmentDraft] {
    drafts = load_assignment_fixture("fixtures/canvas/assignments.json");
    for draft in drafts {
        if draft.due_at {
            draft.due_at = datetime.fromisoformat(draft.due_at).astimezone(parse_zone(zone)).strftime("%Y-%m-%dT%H:%M");
        }
    }
    return drafts;
}

def:protect list_canvas_samples() -> list[CanvasAssignmentDraft] {
    return sample_assignments(ensure_profile().timezone);
}
