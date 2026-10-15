"""Planner endpoints: the Today and Plan screens, the fit preview, and plan actions.

Each call re-plans from the stored tasks and the calendar, so the views always
reflect the latest edits. Nothing is scheduled ahead of time.
"""

import from datetime { datetime, timedelta, timezone }
import from account.schema { ensure_profile, rules_for }
import from breakdown { CognitiveTier }
import from courses.schema { find_task }
import from courses.store { SubtaskDraft, clean_drafts }
import from planner.fit { FitPreview, PREVIEW_GROUP, fit_view, preview_id }
import from planner.inputs { load_inputs }
import from planner.views { TodayView, WeekView, today_view, week_view }
import from scheduling.planner { PlanTask, at_local, local_day, placement_for, plan_tasks }
import from shared.timefmt { parse_due, parse_zone }

glob RESCHEDULE_FALLBACK_HOURS: int = 1;

obj FitResult {
    has ok: bool;
    has error: str = "";
    has preview: FitPreview | None = None;
}

obj ActionResult {
    has ok: bool;
    has error: str = "";
}

def utc_now -> datetime {
    return datetime.now(timezone.utc);
}

def:protect get_today -> TodayView {
    now = utc_now();
    return today_view(load_inputs(now), now);
}

def:protect get_week -> WeekView {
    now = utc_now();
    return week_view(load_inputs(now), now);
}

def proposed_tasks(drafts: list[SubtaskDraft], due: datetime | None) -> list[PlanTask] {
    return [
        PlanTask(
            task_id=preview_id(position),
            title=draft.title,
            tier=CognitiveTier(draft.tier),
            minutes=draft.estimated_duration,
            group_id=PREVIEW_GROUP,
            order=position,
            due=due
        )
        for (position, draft) in enumerate(drafts, start=1)
    ];
}

"""Where the proposed subtasks would land if added now, with the agent's checks."""
def:protect preview_fit(title: str, due_at: str, subtasks: list[SubtaskDraft]) -> FitResult {
    now = utc_now();
    zone = parse_zone(ensure_profile().timezone);
    try {
        due = parse_due(due_at, zone, now) if due_at.strip() else None;
        drafts = clean_drafts(subtasks);
    } except ValueError as err {
        return FitResult(ok=False, error=str(err));
    }
    inputs = load_inputs(now);
    preview = fit_view(inputs, " ".join(title.split()), due, proposed_tasks(drafts, due), now);
    return FitResult(ok=True, preview=preview);
}

"""Not today: keep the subtask off today's plan."""
def:protect skip_task_today(task_id: str) -> ActionResult {
    task = find_task(task_id);
    if task is None {
        return ActionResult(ok=False, error="That subtask no longer exists.");
    }
    rules = rules_for(ensure_profile());
    tomorrow = local_day(utc_now(), rules.zone) + timedelta(days=1);
    task.not_before = at_local(tomorrow, rules.day_start, rules.zone).isoformat();
    return ActionResult(ok=True);
}

"""Reschedule: move the subtask to the next slot after the one it has now."""
def:protect reschedule_task(task_id: str) -> ActionResult {
    task = find_task(task_id);
    if task is None {
        return ActionResult(ok=False, error="That subtask no longer exists.");
    }
    now = utc_now();
    inputs = load_inputs(now);
    plan = plan_tasks(inputs.tasks, inputs.events, inputs.protected, inputs.rules, now);
    current = placement_for(plan, task_id);
    after = current.end if current is not None else now + timedelta(hours=RESCHEDULE_FALLBACK_HOURS);
    task.not_before = after.isoformat();
    return ActionResult(ok=True);
}
