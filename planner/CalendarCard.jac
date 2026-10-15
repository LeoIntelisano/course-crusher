"""The week calendar on Today: Google events with their names and courses, classes, protected hours, planned blocks."""

import from "@jac/runtime" { Link }
import from .grid { grid_height, hour_marks, hour_text, item_box, now_offset }
import from .service { get_calendar }
import from .inputs { CourseChoice }
import from .week_calendar { CalendarDay, CalendarItem, CalendarView }
import from ..courses.store { CourseResult, link_event, unlink_event }
import from ..shell.PlannerContext { usePlanner }
import from ..shared.errors { error_message }
import from ..shared.format { tier_key }
import from ..shared.styles { BUTTON, BUTTON_PRIMARY, BUTTON_SMALL, CARD, COURSE_ACCENT, COURSE_BLOCK, FIELD }
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

glob NOT_A_CLASS: str = "none";

"""Course color for course events; tier color plus a course-colored edge for planned blocks."""
def item_style(item: CalendarItem) -> str {
    if item.kind == "task" {
        return ITEM_TIER[tier_key(item.tier)] + " " + COURSE_ACCENT.get(item.color, "");
    }
    if item.color and item.kind != "busy" and item.kind != "protected" {
        course = COURSE_BLOCK.get(item.color, "");
        return course + " border-dashed opacity-80" if item.kind == "free" else course;
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

def:pub BlockText(item: CalendarItem) -> JsxElement {
    chip = course_chip(item);
    <>
        <div className="truncate font-[650]">{item.title}</div>
        {chip and <div className="mt-px truncate text-[10px] font-semibold uppercase tracking-[.04em] opacity-80">{chip}</div>}
        <div className="truncate text-[10px] opacity-80">{item.detail}</div>
    </>
}

"""One block. Named Google events are buttons that open the course picker."""
def:pub CalendarBlock(item: CalendarItem, gridStart: int, onPick: Callable[[CalendarItem], None]) -> JsxElement {
    box = item_box(item.start_minute, item.end_minute, gridStart, item.lane, item.lanes);
    label = item.title + " · " + item.detail;
    if item.linkable {
        return <button
            type="button"
            className={ITEM_BASE + " cursor-pointer hover:ring-2 hover:ring-ink/20 " + item_style(item)}
            style={box}
            title={label + " · click to link a course"}
            aria-label={f"{item.title}, {item.detail}. Link to a course"}
            data-kind={item.kind}
            data-color={item.color}
            onClick={lambda { onPick(item); }}
        >
            <BlockText item={item} />
        </button>;
    }
    <div className={ITEM_BASE + " " + item_style(item)} style={box} title={label} data-kind={item.kind} data-color={item.color}>
        <BlockText item={item} />
    </div>
}

"""Pick the course for every event with this name, or mark it "not a class"."""
def:pub EventLinker(
    item: CalendarItem,
    courses: list[CourseChoice],
    busy: bool,
    onLink: Callable[[str, str], None],
    onUnlink: Callable[[str], None],
    onClose: Callable[[], None]
) -> JsxElement {
    has choice: str = "";
    current = [c.id for c in courses if c.code == item.course_code];
    fallback = current[0] if current else (NOT_A_CLASS if item.linked else "");
    selected = choice or fallback;

    def save(e: FormEvent) {
        e.preventDefault();
        if selected {
            onLink(item.title, "" if selected == NOT_A_CLASS else selected);
        }
    }

    <form className="mx-2 mb-3 rounded-md border border-line-strong bg-canvas p-3 desk:mx-4" onSubmit={save} aria-label={f"Link {item.title} to a course"}>
        <div className="text-[13px] font-[650]">{item.title}</div>
        <div className="text-[11.5px] text-muted">{item.detail}</div>
        <div className="mt-2 flex flex-wrap items-end gap-2">
            <label className="flex flex-col text-[12px] font-[650]" htmlFor="link-course">
                Course
                <select id="link-course" className={FIELD + " mt-1 w-auto"} value={selected} onChange={lambda (e: ChangeEvent) { choice = e.target.value; }}>
                    <option value="">Choose a course</option>
                    {for course in courses { <option key={course.id} value={course.id}>{course.code}</option> }}
                    <option value={NOT_A_CLASS}>Not a class</option>
                </select>
            </label>
            <button type="submit" className={BUTTON_PRIMARY} disabled={busy or not selected}>Save link</button>
            {item.linked and <button type="button" className={BUTTON} disabled={busy} onClick={lambda { onUnlink(item.title); }}>Use automatic matching</button>}
            <button type="button" className={BUTTON_SMALL} onClick={lambda { onClose(); }}>Close</button>
        </div>
        <p className="mt-2 mb-0 text-[11.5px] text-muted">{"Applies to every event named “" + item.title + "”, now and in future weeks."}</p>
    </form>
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
            <div key={f"{day.iso_date}-all-{index}"} className={"truncate rounded-[5px] px-1.5 py-0.5 text-[10.5px] font-semibold " + (COURSE_BLOCK.get(all_day.color, "") if all_day.color else "bg-canvas text-body")} title={all_day.title}>
                {all_day.title}{all_day.course_code and f" · {all_day.course_code}"}
            </div>
        }}
    </div>
}

def:pub DayBody(day: CalendarDay, view: CalendarView, visible: bool, onPick: Callable[[CalendarItem], None]) -> JsxElement {
    height = grid_height(view.start_minute, view.end_minute);
    line = now_offset(view.now_minute, view.start_minute, view.end_minute) if day.is_today else -1;
    <div className={column_class(visible) + " relative"} style={{"height": f"{height}px"}} aria-label={f"{day.weekday} {day.date_label}"}>
        {for hour in hour_marks(view.start_minute, view.end_minute) {
            <div key={f"{day.iso_date}-h{hour}"} className="absolute inset-x-0 border-t border-line/70" style={{"top": f"{grid_height(view.start_minute, hour * 60)}px"}}></div>
        }}
        {for item in day.items {
            <CalendarBlock key={item.key} item={item} gridStart={view.start_minute} onPick={onPick} />
        }}
        {line >= 0 and <div className="absolute inset-x-0 z-10 border-t-2 border-danger" style={{"top": f"{line}px"}} aria-label="Now"></div>}
    </div>
}

def:pub WeekGrid(view: CalendarView, selected: int, onPick: Callable[[CalendarItem], None]) -> JsxElement {
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
                <DayBody key={day.iso_date} day={day} view={view} visible={index == selected} onPick={onPick} />
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
    has picked: CalendarItem | None = None;
    has linking: bool = False;

    async def applyLink(result: CourseResult | None) -> None {
        linking = False;
        if result and not result.ok {
            failure = result.error;
            return;
        }
        picked = None;
        await ctx.refreshToday();
    }

    async def saveLink(title: str, course_id: str) -> None {
        linking = True;
        result: CourseResult | None = None;
        try {
            result = await link_event(title, course_id);
        } except Exception as err {
            failure = error_message(err);
            linking = False;
            return;
        }
        await applyLink(result);
    }

    async def resetLink(title: str) -> None {
        linking = True;
        result: CourseResult | None = None;
        try {
            result = await unlink_event(title);
        } except Exception as err {
            failure = error_message(err);
            linking = False;
            return;
        }
        await applyLink(result);
    }

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
            <WeekGrid view={view} selected={selected} onPick={lambda (item: CalendarItem) { picked = item; }} />
            if picked is not None {
                <EventLinker
                    key={picked.key}
                    item={picked}
                    courses={view.courses}
                    busy={linking}
                    onLink={saveLink}
                    onUnlink={resetLink}
                    onClose={lambda { picked = None; }}
                />
            }
        }}
        {if view is None and not failure {
            <p className="m-0 px-4 pb-4 text-[12.5px] text-muted">Loading the calendar…</p>
        }}
    </section>
}
