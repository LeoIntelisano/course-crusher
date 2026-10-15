"""The week calendar on Today: Google events with their names and courses, classes, protected hours, planned blocks."""

import from "@jac/runtime" { Link }
import from .grid { grid_height, hour_marks, hour_text, item_box, now_offset }
import from .service { get_calendar }
import from .week_calendar { CalendarDay, CalendarItem, CalendarView }
import from ..shell.PlannerContext { usePlanner }
import from ..shared.errors { error_message }
import from ..shared.format { tier_key }
import from ..shared.styles { BUTTON_SMALL, CARD }
import from ..shared.ui { CardHeader, Notice }

glob ITEM_BASE: str = "absolute overflow-hidden rounded-[6px] px-1.5 py-1 text-left text-[11px] leading-[1.25]";
glob ITEM_KIND: dict[str, str] = {
    "class": "border border-line bg-fixed-bg text-fixed",
    "event": "border border-line-strong bg-surface text-text shadow-[0_1px_1px_rgba(18,21,26,.04)]",
    "busy": "border border-line bg-fixed-bg text-fixed",
    "free": "border border-dashed border-line-strong bg-surface/70 text-muted",
    "protected": "border border-dashed border-line-strong bg-transparent text-faint"
};
glob ITEM_TIER: dict[str, str] = {
    "deep": "border border-deep-line bg-deep-bg text-deep",
    "shallow": "border border-shallow-line bg-shallow-bg text-shallow",
    "low": "border border-low-line bg-low-bg text-low"
};
glob DAY_TAB: str = "flex min-w-[44px] flex-col items-center rounded-sm border border-line px-2 py-1 text-[11px] font-semibold text-muted";
glob DAY_TAB_ON: str = "flex min-w-[44px] flex-col items-center rounded-sm border border-ink bg-ink px-2 py-1 text-[11px] font-semibold text-white";

def item_style(item: CalendarItem) -> str {
    if item.kind == "task" {
        return ITEM_TIER[tier_key(item.tier)];
    }
    return ITEM_KIND.get(item.kind, ITEM_KIND["event"]);
}

"""Show the course chip only when the title doesn't already say it."""
def course_chip(item: CalendarItem) -> str {
    if item.course_code and item.course_code.lower() not in item.title.lower() {
        return item.course_code;
    }
    return "";
}

def:pub CalendarBlock(item: CalendarItem, gridStart: int) -> JsxElement {
    chip = course_chip(item);
    <div
        className={ITEM_BASE + " " + item_style(item)}
        style={item_box(item.start_minute, item.end_minute, gridStart, item.lane, item.lanes)}
        title={item.title + " · " + item.detail}
        data-kind={item.kind}
    >
        <div className="truncate font-[650]">{item.title}</div>
        {chip and <div className="mt-px truncate text-[10px] font-semibold uppercase tracking-[.04em] opacity-80">{chip}</div>}
        <div className="truncate text-[10px] opacity-80">{item.detail}</div>
    </div>
}

glob AXIS: str = "w-11 flex-none";

def column_class(visible: bool) -> str {
    return "min-w-0 flex-1 border-l border-line " + ("block" if visible else "hidden desk:block");
}

def:pub DayHeader(day: CalendarDay, visible: bool) -> JsxElement {
    <div
        className={column_class(visible) + " px-1.5 py-1.5 text-center " + ("bg-brand-bg" if day.is_today else "bg-surface")}
        data-today={"true" if day.is_today else None}
    >
        <div className={"text-[11px] font-[650] uppercase tracking-[.06em] " + ("text-brand" if day.is_today else "text-muted")}>{day.weekday}</div>
        <div className="text-[12px] tabular-nums text-faint">{day.date_label}</div>
    </div>
}

def:pub AllDayCell(day: CalendarDay, visible: bool) -> JsxElement {
    <div className={column_class(visible) + " flex flex-col gap-0.5 p-0.5"}>
        {for (index, all_day) in enumerate(day.all_day) {
            <div key={f"{day.iso_date}-all-{index}"} className="truncate rounded-[5px] bg-canvas px-1.5 py-0.5 text-[10.5px] font-semibold text-body" title={all_day.title}>
                {all_day.title}{all_day.course_code and f" · {all_day.course_code}"}
            </div>
        }}
    </div>
}

def:pub DayBody(day: CalendarDay, view: CalendarView, visible: bool) -> JsxElement {
    height = grid_height(view.start_minute, view.end_minute);
    line = now_offset(view.now_minute, view.start_minute, view.end_minute) if day.is_today else -1;
    <div className={column_class(visible) + " relative"} style={{"height": f"{height}px"}} aria-label={f"{day.weekday} {day.date_label}"}>
        {for hour in hour_marks(view.start_minute, view.end_minute) {
            <div key={f"{day.iso_date}-h{hour}"} className="absolute inset-x-0 border-t border-line/70" style={{"top": f"{grid_height(view.start_minute, hour * 60)}px"}}></div>
        }}
        {for item in day.items {
            <CalendarBlock key={item.key} item={item} gridStart={view.start_minute} />
        }}
        {line >= 0 and <div className="absolute inset-x-0 z-10 border-t-2 border-danger" style={{"top": f"{line}px"}} aria-label="Now"></div>}
    </div>
}

def:pub WeekGrid(view: CalendarView, selected: int) -> JsxElement {
    has_all_day = len([d for d in view.days if len(d.all_day) > 0]) > 0;
    <div className="px-2 pt-2 pb-3 desk:px-4">
        <div className="flex border-b border-r border-line">
            <div className={AXIS}></div>
            {for (index, day) in enumerate(view.days) {
                <DayHeader key={day.iso_date} day={day} visible={index == selected} />
            }}
        </div>
        {if has_all_day {
            <div className="flex border-b border-r border-line">
                <div className={AXIS + " pt-1 pr-1.5 text-right text-[10px] text-faint"}>all day</div>
                {for (index, day) in enumerate(view.days) {
                    <AllDayCell key={day.iso_date} day={day} visible={index == selected} />
                }}
            </div>
        }}
        <div className="flex border-r border-line">
            <div className={AXIS + " relative"} style={{"height": f"{grid_height(view.start_minute, view.end_minute)}px"}}>
                {for hour in hour_marks(view.start_minute, view.end_minute) {
                    <div key={f"axis-{hour}"} className="absolute right-1.5 text-[10.5px] tabular-nums text-faint" style={{"top": f"{grid_height(view.start_minute, hour * 60)}px"}}>
                        {hour_text(hour)}
                    </div>
                }}
            </div>
            {for (index, day) in enumerate(view.days) {
                <DayBody key={day.iso_date} day={day} view={view} visible={index == selected} />
            }}
        </div>
    </div>
}

def:pub CalendarCard -> JsxElement {
    ctx: any = usePlanner();
    has view: CalendarView | None = None;
    has week_offset: int = 0;
    has selected: int = 0;
    has failure: str = "";

    async def load(offset: int) -> None {
        latest: CalendarView | None = None;
        try {
            latest = await get_calendar(offset);
        } except Exception as err {
            failure = error_message(err);
            return;
        }
        failure = "";
        view = latest;
        today_index = [i for (i, d) in enumerate(latest.days) if d.is_today] if latest else [];
        selected = today_index[0] if today_index else 0;
    }

    # reload when the week changes or anything re-plans the day
    async can with (week_offset, ctx.today) entry {
        await load(week_offset);
    }

    <section className={CARD} aria-labelledby="calendar-h">
        <CardHeader title="Calendar" titleId="calendar-h">
            <span className="hidden text-[11.5px] text-faint desk:inline">{view.range_label if view else ""}</span>
            <span className="ml-auto flex items-center gap-1.5">
                <button type="button" className={BUTTON_SMALL} aria-label="Previous week" onClick={lambda { week_offset = week_offset - 1; }}>‹</button>
                <button type="button" className={BUTTON_SMALL + " whitespace-nowrap"} disabled={week_offset == 0} onClick={lambda { week_offset = 0; }}>This week</button>
                <button type="button" className={BUTTON_SMALL} aria-label="Next week" onClick={lambda { week_offset = week_offset + 1; }}>›</button>
            </span>
        </CardHeader>
        <div className="flex flex-col gap-2 px-4 pt-2">
            <Notice tone="error" message={failure} />
            {if view is not None and not view.connected {
                <p className="m-0 text-[11.5px] text-muted">
                    Showing classes and your plan. <Link to="/connections" className="font-semibold text-brand">Connect Google Calendar</Link> to see your events here too.
                </p>
            }}
            {if view is not None and view.connected and not view.names {
                <p className="m-0 text-[11.5px] text-muted">
                    Google events show as "Busy". <Link to="/connections" className="font-semibold text-brand">Reconnect Google Calendar</Link> to see their names and match them to your courses.
                </p>
            }}
        </div>
        {if view is not None {
            <div className="flex gap-1.5 overflow-x-auto px-4 pt-2 desk:hidden" role="tablist" aria-label="Day">
                {for (index, day) in enumerate(view.days) {
                    <button
                        key={day.iso_date}
                        type="button"
                        role="tab"
                        aria-selected={index == selected}
                        className={DAY_TAB_ON if index == selected else DAY_TAB}
                        onClick={lambda { selected = index; }}
                    >
                        <span>{day.weekday}</span>
                        <span className="tabular-nums opacity-80">{day.date_label.split(" ")[1]}</span>
                    </button>
                }}
            </div>
            <WeekGrid view={view} selected={selected} />
        }}
        {if view is None and not failure {
            <p className="m-0 px-4 pb-4 text-[12.5px] text-muted">Loading the calendar…</p>
        }}
    </section>
}
