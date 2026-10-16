"""Plan: the next seven days, the same rows as Today grouped by day."""

import from .service { get_week }
import from .views { DayPlan, PlanItem, WeekView }
import from ..courses.store { CourseResult, set_task_done }
import from ..shell.PlannerContext { usePlanner }
import from ..shared.errors { error_message }
import from ..shared.format { format_minutes, tier_key }
import from ..shared.styles { CARD, ROW_DOT }
import from ..shared.ui { CardHeader, EmptyState, Notice, TierChip }

def:pub PlanRow(item: PlanItem, busy: bool, onDone: Callable[[str], None]) -> JsxElement {
    def handle_done(e: MouseEvent) {
        onDone(item.task_id);
    }
    <li className="flex items-start gap-3 px-4 py-2.5 desk:items-center">
        <span className={ROW_DOT[tier_key(item.tier)]} aria-hidden="true"></span>
        <span className="w-[118px] flex-none text-[12.5px] font-semibold tabular-nums">{item.range_label}</span>
        <span className="min-w-0 flex-1">
            <div className="text-[13.5px] font-semibold tracking-[-0.1px]">{item.title}</div>
            <div className="mt-1 flex flex-wrap items-center gap-1.5 text-[12px] text-muted">
                <TierChip tier={item.tier} />
                <span>{f"{item.course_code} · {item.assignment_title}"}</span>
                {item.late and <span className="font-semibold text-danger">after the deadline</span>}
            </div>
        </span>
        <button
            type="button"
            disabled={busy}
            onClick={handle_done}
            aria-label={f"Mark {item.title} done"}
            className="grid h-7 w-7 flex-none place-items-center rounded-sm border border-line-strong bg-surface text-[12px] text-muted hover:border-ink hover:text-ink disabled:opacity-60"
        >
            ✓
        </button>
    </li>
}

def:pub DayCard(day: DayPlan, busy: bool, onDone: Callable[[str], None]) -> JsxElement {
    heading_id = "day-" + day.date_label.replace(" ", "-").replace(",", "");
    aside = format_minutes(day.total_minutes) + " planned" if day.total_minutes else "Open";
    <section className={CARD} aria-labelledby={heading_id}>
        <CardHeader title={f"{day.day_label} · {day.date_label}" if day.day_label in ["Today", "Tomorrow"] else day.date_label} titleId={heading_id} aside={aside} />
        <ul className="m-0 list-none divide-y divide-line p-0 pt-1.5 pb-1.5">
            {for item in day.items {
                <PlanRow key={item.task_id} item={item} busy={busy} onDone={onDone} />
            }}
            {for event in day.events {
                <li key={event.start + event.title} className="flex items-center gap-3 px-4 py-2 text-[12.5px] text-muted">
                    <span className="h-[9px] w-[9px] flex-none rounded-full border border-line-strong" aria-hidden="true"></span>
                    <span className="w-[118px] flex-none tabular-nums">{event.detail.split(" · ")[0]}</span>
                    <span>{event.title}</span>
                </li>
            }}
            {if len(day.items) == 0 and len(day.events) == 0 {
                <li className="px-4 py-2.5 text-[12.5px] text-muted">Nothing planned.</li>
            }}
        </ul>
    </section>
}

def:pub WeekBoard(week: WeekView, busy: bool, onDone: Callable[[str], None]) -> JsxElement {
    <div className="flex flex-col gap-[13px]">
        {if week.at_risk > 0 {
            <Notice tone="error" message={f"{week.at_risk} deadline(s) at risk: some steps land late or don't fit this week."} />
        }}
        {for day in week.days {
            <DayCard key={day.date_label} day={day} busy={busy} onDone={onDone} />
        }}
        {if len(week.unplaced) > 0 {
            <section className={CARD + " border-danger/40"} aria-labelledby="plan-unplaced">
                <CardHeader title="Doesn't fit this week" titleId="plan-unplaced" />
                <ul className="m-0 list-none divide-y divide-line px-4 py-1.5">
                    {for item in week.unplaced {
                        <li key={item.task_id} className="py-2 text-[12.5px]">
                            <span className="font-semibold">{item.title}</span>
                            <span className="text-muted">{f" · {item.course_code} · {item.minutes} min"}</span>
                        </li>
                    }}
                </ul>
            </section>
        }}
    </div>
}

def:pub PlanPage -> JsxElement {
    ctx: any = usePlanner();
    has week: WeekView | None = None;
    has failure: str = "";
    has busy: bool = False;

    async def load -> None {
        latest: WeekView | None = None;
        try {
            latest = await get_week();
        } except Exception as err {
            failure = error_message(err);
            return;
        }
        week = latest;
        failure = "";
    }

    async def markDone(task_id: str) -> None {
        busy = True;
        result: CourseResult | None = None;
        try {
            result = await set_task_done(task_id, True);
        } except Exception as err {
            failure = error_message(err);
            busy = False;
            return;
        }
        if result and not result.ok {
            failure = result.error;
        }
        await load();
        await ctx.refreshToday();
        busy = False;
    }

    async can with entry {
        await load();
    }

    <div className="mx-auto flex max-w-[860px] flex-col gap-[13px]">
        <Notice tone="error" message={failure} />
        {if week is None {
            <section className={CARD}><EmptyState title="Loading your week…" detail="" /></section>
        } else {
            <WeekBoard week={week} busy={busy} onDone={markDone} />
        }}
    </div>
}
