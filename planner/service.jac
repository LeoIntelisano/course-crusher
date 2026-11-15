"""Planner endpoints: the Today and Plan screens, the fit preview, and plan actions.

Each call re-plans from the stored tasks and the calendar, so the views always
reflect the latest edits. Nothing is scheduled ahead of time.
"""

import from datetime { datetime, time, timedelta, timezone }
import from account.schema { ensure_profile, rules_for }
import from breakdown { CognitiveTier }
import from courses.schema { find_task }
import from courses.store { SubtaskDraft, clean_drafts }
import from planner.week_calendar { CalendarView, calendar_view, clamp_offset, week_start }
import from planner.fit { FitPreview, PREVIEW_GROUP, fit_view, preview_id }
import from planner.inputs { load_inputs }
import from planner.views { TodayView, WeekView, today_view, week_view }
import from scheduling.planner {
    MAX_HORIZON_DAYS,
    PlanTask,
    at_local,
    local_day,
    placement_for,
    plan_tasks
}
import from shared.timefmt { parse_due, parse_zone }

glob RESCHEDULE_FALLBACK_HOURS: int = 1;
glob MAX_CLOSE_OUT: int = 50;

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

"""One week of the calendar: 0 is this week, -1 last week, 1 next week."""
def:protect get_calendar(week_offset: int) -> CalendarView {
    now = utc_now();
    rules = rules_for(ensure_profile());
    offset = clamp_offset(week_offset);
    first = week_start(now, rules, offset);
    show_from = at_local(first, time(0), rules.zone);
    show_until = at_local(first + timedelta(days=7), time(0), rules.zone);
    days_to_week_end = (first + timedelta(days=7) - local_day(now, rules.zone)).days;
    horizon = max(1, min(MAX_HORIZON_DAYS, max(rules.horizon_days, days_to_week_end)));
    inputs = load_inputs(now, show_from, show_until, horizon);
    return calendar_view(inputs, now, offset);
}

def proposed_tasks(drafts: list[SubtaskDraft], due: datetime | None, starts: list[datetime | None] = []) -> list[PlanTask] {
    return [
        PlanTask(
            task_id=preview_id(position),
            title=draft.title,
            tier=CognitiveTier(draft.tier),
            minutes=draft.estimated_duration,
            group_id=PREVIEW_GROUP,
            order=position,
            due=due,
            fixed_start=starts[position - 1] if position <= len(starts) else None
        )
        for (position, draft) in enumerate(drafts, start=1)
    ];
}

"""Where the proposed subtasks would land if added now, with the agent's checks."""
def:protect preview_fit(title: str, due_at: str, subtasks: list[SubtaskDraft], manual_starts: list[str] | None = None) -> FitResult {
    now = utc_now();
    if not isinstance(manual_starts, list) {
        manual_starts = [];
    }
    zone = parse_zone(ensure_profile().timezone);
    try {
        due = parse_due(due_at, zone, now) if due_at.strip() else None;
        drafts = clean_drafts(subtasks);
        starts: list[datetime | None] = [];
        for (position, draft) in enumerate(drafts) {
            raw = manual_starts[position].strip() if position < len(manual_starts) else "";
            if not raw {
                starts = starts + [None];
                continue;
            }
            parsed = datetime.fromisoformat(raw);
            if parsed.tzinfo is None {
                parsed = parsed.replace(tzinfo=zone);
            } else {
                parsed = parsed.astimezone(zone);
            }
            if parsed <= now {
                raise ValueError(f"Subtask {position + 1}: choose a future start time.");
            }
            starts = starts + [parsed];
        }
        # A manually chosen slot cannot precede an earlier, manually chosen step.
        for i in range(len(starts)) {
            if starts[i] is None {
                continue;
            }
            for j in range(i) {
                if starts[j] is not None and starts[i] < starts[j] + timedelta(minutes=drafts[j].estimated_duration) {
                    raise ValueError("Manually scheduled subtasks of the same assignment must follow their breakdown order without overlapping.");
                }
            }
        }
    } except ValueError as err {
        return FitResult(ok=False, error=str(err));
    }
    inputs = load_inputs(now);
    proposed = proposed_tasks(drafts, due, starts);
    plan = plan_tasks(inputs.tasks + proposed, inputs.events, inputs.protected, inputs.rules, now);
    for (i, start) in enumerate(starts) {
        if start is None {
            continue;
        }
        spot = placement_for(plan, proposed[i].task_id);
        if spot is None or not spot.fixed or spot.start != start {
            return FitResult(ok=False, error=f"Subtask {i + 1}: that time is unavailable. Choose another date or time.");
        }
    }
    # Fixed placements are decided first; verify they do not jump ahead of earlier steps.
    for (i, start) in enumerate(starts) {
        if start is None {
            continue;
        }
        current = placement_for(plan, proposed[i].task_id);
        for j in range(i) {
            earlier = placement_for(plan, proposed[j].task_id);
            if earlier is None or current is None or earlier.end > current.start {
                return FitResult(ok=False, error=f"Subtask {i + 1} must start after the earlier subtasks in this assignment.");
            }
        }
    }
    # Don't silently shift someone else's already-approved work.
    original = plan_tasks(inputs.tasks, inputs.events, inputs.protected, inputs.rules, now);
    for item in inputs.tasks {
        if item.fixed_start is None {
            continue;
        }
        before = placement_for(original, item.task_id);
        after = placement_for(plan, item.task_id);
        if before is not None and before.fixed and (after is None or not after.fixed or after.start != before.start) {
            return FitResult(ok=False, error="That time conflicts with an already approved assignment.");
        }
    }
    preview = fit_view(inputs, " ".join(title.split()), due, proposed, now);
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
    task.approved_start = "";
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
    task.approved_start = "";
    return ActionResult(ok=True);
}

"""Not yet: an approved block passed without the work getting done. Release its time so the planner re-places it."""
def:protect release_task(task_id: str) -> ActionResult {
    task = find_task(task_id);
    if task is None {
        return ActionResult(ok=False, error="That subtask no longer exists.");
    }
    task.approved_start = "";
    return ActionResult(ok=True);
}

"""Close out several subtasks at once, e.g. everything Plan lists under "Earlier today"."""
def:protect complete_tasks(task_ids: list[str]) -> ActionResult {
    if not task_ids {
        return ActionResult(ok=False, error="Pick at least one subtask to mark done.");
    }
    if len(task_ids) > MAX_CLOSE_OUT {
        return ActionResult(ok=False, error=f"Mark at most {MAX_CLOSE_OUT} subtasks done at once.");
    }
    tasks = [task for task in [find_task(task_id) for task_id in task_ids] if task is not None];
    if not tasks {
        return ActionResult(ok=False, error="Those subtasks no longer exist.");
    }
    finished_at = utc_now().isoformat();
    for task in tasks {
        task.done = True;
        task.completed_at = finished_at;
    }
    return ActionResult(ok=True);
}
