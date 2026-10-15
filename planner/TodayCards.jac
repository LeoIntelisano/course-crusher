"""The Today screen's cards. Stateless: data comes in as props, actions go out as callbacks."""

import from "@jac/runtime" { Link }
import from .FocusTimer { FocusTimer }
import from .views { PlanItem, TimelineBlock, WeekLoad }
import from ..connections.google_link { CalendarStatus }
import from ..shared.format { format_minutes, tier_key }
import from ..shared.styles { BLOCK, BUTTON, BUTTON_GHOST, BUTTON_PRIMARY, CARD, ROW_DOT, TIER_BAR, TIER_DOT }
import from ..shared.ui { CardHeader, PlainChip, TierChip, WarnChip }

glob HERO_BUTTON: str = "flex-1 min-h-[46px] desk:flex-none desk:min-h-0";
glob RISK_BAR_STEP: int = 20;
glob URGENT_DAYS: int = 2;

def days_left_text(days: int) -> str {
    if days == 0 {
        return "Due today";
    }
    if days == 1 {
        return "1 day left";
    }
    return f"{days} days left";
}

def:pub UpNextCard(
    item: PlanItem,
    why: str,
    swapped: bool,
    focusing: bool,
    busy: bool,
    canSwap: bool,
    onStart: Callable[[], None],
    onStop: Callable[[], None],
    onDone: Callable[[], None],
    onReschedule: Callable[[], None],
    onSwap: Callable[[], None],
    onSkip: Callable[[], None]
) -> JsxElement {
    course = item.course_code + " · " + item.assignment_title;
    due = f"  ·  due {item.due_label}" if item.due_label else "";
    <section className={CARD + " border-line-strong px-4 py-4 shadow-[0_1px_2px_rgba(18,21,26,.05)] desk:px-5 desk:py-[18px]"} aria-labelledby="upnext">
        <div className="flex items-center gap-2 text-[10.5px] font-[650] uppercase tracking-[.09em] text-muted">
            <span id="upnext">Up next</span>
            <span className="inline-flex items-center gap-[5px] text-brand"><span className="text-[11px]" aria-hidden="true">✦</span>Agent pick</span>
        </div>
        <h3 className="mt-[9px] mb-0 max-w-[46ch] text-[18px] font-[650] leading-[1.3] tracking-[-0.4px] desk:text-[20px]">{item.title}</h3>
        <div className="mt-[5px] text-[13px] text-muted">{course + due}</div>
        <div className="mt-3 flex flex-wrap gap-[7px]">
            <TierChip tier={item.tier} />
            <PlainChip text={f"{item.minutes} min"} />
            <PlainChip text={f"Fits {item.range_label}" if item.day_label == "Today" else f"{item.day_label} {item.range_label}"} />
            {0 <= item.days_left <= URGENT_DAYS and <WarnChip text={days_left_text(item.days_left)} />}
        </div>
        <p className="mt-[13px] mb-0 rounded-md border border-line bg-canvas px-[13px] py-[11px] text-[12.5px] leading-normal text-body">
            {"Swapped in from later today." if swapped else ""}
            {not swapped and <b className="font-[650] text-text">Why now:</b>}
            {"" if swapped else " " + why}
        </p>
        {focusing and <FocusTimer minutes={item.minutes} onDone={onDone} onStop={onStop} />}
        {not focusing and <div className="mt-[15px] flex flex-wrap gap-2 desk:gap-[9px]">
            <button type="button" className={BUTTON_PRIMARY + " basis-full min-h-[46px] desk:basis-auto desk:min-h-0"} disabled={busy} onClick={lambda { onStart(); }}>
                {f"Start {item.minutes}-min focus"}
            </button>
            <button type="button" className={BUTTON + " " + HERO_BUTTON} disabled={busy} onClick={lambda { onReschedule(); }}>Reschedule</button>
            <button type="button" className={BUTTON + " " + HERO_BUTTON} disabled={busy or not canSwap} onClick={lambda { onSwap(); }}>Swap task</button>
            <button type="button" className={BUTTON_GHOST + " basis-full min-h-[40px] desk:basis-auto desk:min-h-0"} disabled={busy} onClick={lambda { onSkip(); }}>Not today</button>
        </div>}
    </section>
}

def:pub QueueRow(item: PlanItem, busy: bool, onDone: Callable[[str], None]) -> JsxElement {
    def handle_done(e: MouseEvent) {
        onDone(item.task_id);
    }
    <div className="flex min-h-[60px] items-start gap-3 rounded-md px-3 pt-[13px] pb-[9px] desk:min-h-[52px] desk:items-center desk:py-[9px]">
        <span className={ROW_DOT[tier_key(item.tier)]} aria-hidden="true"></span>
        <span className="min-w-0 flex-1">
            <div className="text-[13.5px] font-semibold tracking-[-0.1px] desk:truncate">{item.title}</div>
            <div className="mt-0.5 text-[12px] text-muted">{f"{item.course_code} · {item.tier}"}</div>
        </span>
        <span className="flex flex-none flex-col items-end gap-0.5 desk:flex-row desk:items-center desk:gap-3.5">
            <span className="hidden w-[46px] text-right text-[12px] tabular-nums text-faint desk:block">{f"{item.minutes} min"}</span>
            <span className="text-[12.5px] font-semibold tabular-nums">{item.start_label}</span>
            <button
                type="button"
                disabled={busy}
                onClick={handle_done}
                aria-label={f"Mark {item.title} done"}
                className="grid h-7 w-7 place-items-center rounded-sm border border-line-strong bg-surface text-[12px] text-muted hover:border-ink hover:text-ink disabled:opacity-60"
            >
                ✓
            </button>
        </span>
    </div>
}

def:pub QueueCard(items: list[PlanItem], busy: bool, onDone: Callable[[str], None]) -> JsxElement {
    <section className={CARD} aria-labelledby="queue">
        <CardHeader title="Then, if the day holds" titleId="queue">
            <span className="ml-auto hidden items-center gap-3 desk:flex">
                <span className="inline-flex items-center gap-[5px] text-[11px] text-muted"><span className={TIER_DOT["deep"]}></span>Deep</span>
                <span className="inline-flex items-center gap-[5px] text-[11px] text-muted"><span className={TIER_DOT["shallow"]}></span>Shallow</span>
                <span className="inline-flex items-center gap-[5px] text-[11px] text-muted"><span className={TIER_DOT["low"]}></span>Low energy</span>
            </span>
        </CardHeader>
        <div className="divide-y divide-line p-2">
            {if len(items) == 0 {
                <p className="m-0 px-3 py-4 text-[12.5px] text-muted">Nothing else is planned for today.</p>
            }}
            {for item in items {
                <QueueRow key={item.task_id} item={item} busy={busy} onDone={onDone} />
            }}
        </div>
    </section>
}

def percent(part: int, total: int) -> int {
    if total <= 0 {
        return 0;
    }
    return round(part * 100 / total);
}

def:pub LoadStat(value: str, label: str, bar: str, width: int) -> JsxElement {
    <div>
        <div className="text-[21px] font-[650] tracking-[-0.6px] tabular-nums">{value}</div>
        <div className="mt-px text-[11.5px] text-muted">{label}</div>
        <div className="mt-[9px] h-1 overflow-hidden rounded-full bg-canvas">
            <i className={TIER_BAR[bar]} style={{"width": f"{width}%"}}></i>
        </div>
    </div>
}

def:pub WeekLoadCard(week: WeekLoad) -> JsxElement {
    total = week.deep_minutes + week.shallow_minutes + week.low_minutes;
    <section className={CARD} aria-labelledby="week">
        <CardHeader title="This week" titleId="week" aside={week.range_label} />
        <div className="grid grid-cols-2 gap-x-[18px] gap-y-3.5 px-4 pt-[11px] pb-3.5 desk:grid-cols-4 desk:gap-[18px]">
            <LoadStat value={format_minutes(week.deep_minutes)} label="Deep Work booked" bar="deep" width={percent(week.deep_minutes, total)} />
            <LoadStat value={format_minutes(week.shallow_minutes)} label="Shallow Work" bar="shallow" width={percent(week.shallow_minutes, total)} />
            <LoadStat value={format_minutes(week.low_minutes)} label="Low Energy" bar="low" width={percent(week.low_minutes, total)} />
            <LoadStat value={str(week.at_risk)} label="Deadlines at risk" bar="risk" width={min(100, week.at_risk * RISK_BAR_STEP)} />
        </div>
    </section>
}

def block_style(block: TimelineBlock) -> str {
    if block.kind == "task" {
        return BLOCK[tier_key(block.tier)];
    }
    return BLOCK.get(block.kind, BLOCK["event"]);
}

def:pub Timeline(blocks: list[TimelineBlock], emptyText: str) -> JsxElement {
    <div className="px-4 pt-3 pb-4">
        {if len(blocks) == 0 {
            <p className="m-0 py-2 text-[12.5px] text-muted">{emptyText}</p>
        }}
        {for (index, block) in enumerate(blocks) {
            <div key={f"{index}-{block.start}"} className="grid min-h-[34px] grid-cols-[44px_1fr] gap-2.5">
                <span className="pt-[9px] text-right text-[11px] tabular-nums text-faint">{block.hour_label}</span>
                <span className="border-t border-line py-1">
                    <div className={block_style(block)}>
                        <div className="font-[650]">{block.title}</div>
                        <div className="mt-px text-[10.5px] opacity-90">{block.detail}</div>
                    </div>
                </span>
            </div>
        }}
    </div>
}

def:pub TimelineCard(blocks: list[TimelineBlock]) -> JsxElement {
    <section className={CARD} aria-labelledby="plan">
        <CardHeader title="Today's plan" titleId="plan" aside="auto-fitted" />
        <Timeline blocks={blocks} emptyText="Nothing on the calendar today." />
    </section>
}

def calendar_label(status: CalendarStatus) -> str {
    if status.state == "connected" {
        return "Connected" if status.names else "Busy times only";
    }
    if status.state == "error" {
        return "Needs attention";
    }
    if status.state == "not_configured" {
        return "Not set up";
    }
    return "Not connected";
}

def:pub ConnectionsCard(calendar: CalendarStatus) -> JsxElement {
    healthy = calendar.state == "connected";
    <section className={CARD} aria-labelledby="conns">
        <CardHeader title="Connections" titleId="conns">
            <Link to="/connections" className="ml-auto text-[11.5px] font-semibold text-brand">Manage</Link>
        </CardHeader>
        <div className="divide-y divide-line px-4 pt-1.5 pb-3.5">
            <div className="flex items-center gap-2.5 py-[9px] text-[12.5px]">
                <span className="grid h-6 w-6 place-items-center rounded-md border border-line bg-canvas text-[11px] font-bold text-muted">GC</span>
                <span className="font-semibold">Google Calendar</span>
                <span className={"ml-auto inline-flex items-center gap-[5px] text-[11.5px] " + ("text-brand" if healthy else "text-danger")}>
                    <i className={"inline-block h-1.5 w-1.5 rounded-full " + ("bg-brand" if healthy else "bg-danger")}></i>
                    {calendar_label(calendar)}
                </span>
            </div>
            <div className="flex items-center gap-2.5 py-[9px] text-[12.5px]">
                <span className="grid h-6 w-6 place-items-center rounded-md border border-line bg-canvas text-[11px] font-bold text-muted">Cv</span>
                <span className="font-semibold">Canvas</span>
                <span className="ml-auto text-[11.5px] text-muted">Paste on Breakdown</span>
            </div>
        </div>
    </section>
}

def:pub UnplacedCard(items: list[PlanItem]) -> JsxElement {
    <section className={CARD + " border-danger/40"} aria-labelledby="unplaced">
        <CardHeader title="Doesn't fit this week" titleId="unplaced" aside={f"{len(items)} to rethink"} />
        <ul className="m-0 list-none divide-y divide-line px-4 pt-1.5 pb-3">
            {for item in items {
                <li key={item.task_id} className="flex flex-wrap items-center gap-2 py-2 text-[12.5px]">
                    <span className="font-semibold">{item.title}</span>
                    <span className="text-muted">{f"{item.course_code} · {item.minutes} min"}</span>
                    {item.due_label and <span className="ml-auto text-danger">{f"due {item.due_label}"}</span>}
                </li>
            }}
        </ul>
        <p className="m-0 px-4 pb-3.5 text-[11.5px] text-muted">Free up time in Settings or split the step on Breakdown.</p>
    </section>
}
