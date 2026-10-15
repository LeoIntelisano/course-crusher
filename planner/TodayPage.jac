"""Today: the agent's pick, the rest of the day, this week's load, and the fitted timeline."""

import from "@jac/runtime" { Link }
import from .CalendarCard { CalendarCard }
import from .service { ActionResult, reschedule_task, skip_task_today }
import from .TodayCards {
    ConnectionsCard,
    QueueCard,
    TimelineCard,
    UnplacedCard,
    UpNextCard,
    WeekLoadCard
}
import from .views { PlanItem, TodayView }
import from ..courses.store { CourseResult, set_task_done }
import from ..shell.PlannerContext { usePlanner }
import from ..shared.errors { error_message }
import from ..shared.styles { BUTTON_PRIMARY, CARD, CARD_STACK, COLUMNS }
import from ..shared.ui { EmptyState, Notice }

def:pub TodayPage -> JsxElement {
    ctx: any = usePlanner();
    has focusing: bool = False;
    has swap_index: int = 0;
    has busy: bool = False;
    has failure: str = "";

    today: TodayView | None = ctx.today;

    async def markDone(task_id: str) -> None;
    async def reschedule(task_id: str) -> None;
    async def skipToday(task_id: str) -> None;

    if today is None {
        return <section className={CARD}>
            <EmptyState title={"Loading your day…" if ctx.loading else "Your day isn't available"} detail="" />
        </section>;
    }

    candidates: list[PlanItem] = ([today.up_next.item] if today.up_next else []) + today.queue;
    chosen: PlanItem | None = candidates[swap_index % len(candidates)] if candidates else None;
    chosen_id: str = chosen.task_id if chosen is not None else "";

    <div className="flex flex-col gap-[13px]">
    <div className={COLUMNS}>
        <div className={CARD_STACK}>
            <Notice tone="error" message={failure} />
            {if chosen is not None and today.up_next is not None {
                <UpNextCard
                    item={chosen}
                    why={today.up_next.why}
                    swapped={chosen.task_id != today.up_next.item.task_id}
                    focusing={focusing}
                    busy={busy}
                    canSwap={len(candidates) > 1}
                    onStart={lambda { focusing = True; }}
                    onStop={lambda { focusing = False; }}
                    onDone={lambda { markDone(chosen_id); }}
                    onReschedule={lambda { reschedule(chosen_id); }}
                    onSwap={lambda { swap_index = swap_index + 1; focusing = False; }}
                    onSkip={lambda { skipToday(chosen_id); }}
                />
            } elif today.open_tasks == 0 {
                <section className={CARD}>
                    <EmptyState
                        title="Nothing to plan yet"
                        detail="Paste an assignment and the agent will break it down and fit it into your free time."
                    >
                        <div className="mt-4 flex flex-wrap justify-center gap-2">
                            <Link to="/breakdown" className={BUTTON_PRIMARY + " no-underline"}>Break down an assignment</Link>
                            <Link to="/courses" className="inline-flex items-center rounded-sm border border-line-strong bg-surface px-[15px] py-[9px] text-[13px] font-semibold text-text no-underline">Add your classes</Link>
                        </div>
                    </EmptyState>
                </section>
            } else {
                <section className={CARD}>
                    <EmptyState title="No free slot fits your next step" detail="Check the list below, or adjust your day and protected hours in Settings." />
                </section>
            }}
            {len(today.unplaced) > 0 and <UnplacedCard items={today.unplaced} />}
            <QueueCard
                items={[item for item in candidates if item.task_id != chosen_id]}
                busy={busy}
                onDone={markDone}
            />
            <WeekLoadCard week={today.week} />
        </div>
        <div className={CARD_STACK}>
            <TimelineCard blocks={today.timeline} />
            <ConnectionsCard calendar={today.calendar} />
        </div>
    </div>
    <CalendarCard />
    </div>
}
