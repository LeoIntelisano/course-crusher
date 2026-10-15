"""The Breakdown screen's "Where it fits" and "Agent checks" for subtasks not yet saved.

The proposed subtasks are planned alongside everything already in the plan, so
the preview shows the slots they would really get. Nothing is stored.
"""

import from datetime { date, datetime, tzinfo }
import from planner.inputs { PlanningInputs }
import from scheduling.planner {
    PlanGroup,
    PlanTask,
    Placement,
    local_day,
    minutes_between,
    placement_for,
    plan_checks,
    plan_tasks
}
import from shared.format { format_minutes, format_span }
import from shared.timefmt { clock_label, day_label }

glob PREVIEW_GROUP: str = "preview";
glob NOT_PLACED_LABEL: str = "No slot this week";

obj CheckView {
    has level: str;
    has message: str;
}

"""Where one proposed subtask would land. `position` is its 1-based breakdown order."""
obj FitBlock {
    has position: int;
    has title: str;
    has tier: str;
    has minutes: int;
    has placed: bool;
    has when_label: str;
}

"""One row of "Where it fits": a day and what lands on it."""
obj FitDay {
    has day_label: str;
    has title: str;
    has detail: str;
    has tier: str;
}

obj FitPreview {
    has blocks: list[FitBlock];
    has days: list[FitDay];
    has checks: list[CheckView];
    has range_label: str;
    has buffer_label: str;
}

def preview_id(position: int) -> str {
    return f"{PREVIEW_GROUP}-{position}";
}

def fit_day(day: date, steps: list[tuple[PlanTask, Placement]], zone: tzinfo) -> FitDay {
    tiers = {str(task.tier) for (task, _) in steps};
    total = sum([task.minutes for (task, _) in steps]);
    starts = ", ".join([clock_label(p.start.astimezone(zone)) for (_, p) in steps]);
    if len(steps) == 1 {
        title = steps[0][0].title;
    } elif len(tiers) == 1 {
        title = f"{len(steps)} {str(steps[0][0].tier)} blocks";
    } else {
        title = f"{len(steps)} blocks";
    }
    return FitDay(
        day_label=day.strftime("%a"),
        title=title,
        detail=f"{starts} · {format_minutes(total)}",
        tier=str(steps[0][0].tier) if len(tiers) == 1 else ""
    );
}

def fit_view(
    inputs: PlanningInputs, label: str, due: datetime | None, proposed: list[PlanTask], now: datetime
) -> FitPreview {
    rules = inputs.rules;
    today = local_day(now, rules.zone);
    tasks = inputs.tasks + proposed;
    plan = plan_tasks(tasks, inputs.events, inputs.protected, rules, now);
    placed: list[tuple[PlanTask, Placement]] = [];
    blocks: list[FitBlock] = [];
    for task in proposed {
        spot = placement_for(plan, task.task_id);
        when = NOT_PLACED_LABEL;
        if spot is not None {
            local = spot.start.astimezone(rules.zone);
            when = f"{day_label(local.date(), today)} {clock_label(local)}";
            placed = placed + [(task, spot)];
        }
        blocks = blocks + [
            FitBlock(
                position=task.order,
                title=task.title,
                tier=str(task.tier),
                minutes=task.minutes,
                placed=spot is not None,
                when_label=when
            )
        ];
    }
    days_seen = sorted({local_day(p.start, rules.zone) for (_, p) in placed});
    days = [
        fit_day(day, [(t, p) for (t, p) in placed if local_day(p.start, rules.zone) == day], rules.zone)
        for day in days_seen
    ];
    range_label = "";
    if days_seen {
        first = days_seen[0].strftime("%a");
        last = days_seen[-1].strftime("%a");
        range_label = first if first == last else f"{first} – {last}";
    }
    buffer_label = "";
    if due is not None and placed and len(placed) == len(proposed) {
        last_end = max([p.end for (_, p) in placed]);
        if last_end <= due {
            buffer_label = f"{format_span(minutes_between(last_end, due))} of buffer";
        }
    }
    groups = inputs.groups + [PlanGroup(group_id=PREVIEW_GROUP, label=label or "This assignment", due=due)];
    checks = plan_checks(plan, tasks, inputs.events, groups, PREVIEW_GROUP, rules);
    return FitPreview(
        blocks=blocks,
        days=days,
        checks=[CheckView(level=str(c.level), message=c.message) for c in checks],
        range_label=range_label,
        buffer_label=buffer_label
    );
}
