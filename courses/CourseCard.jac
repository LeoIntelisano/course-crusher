"""One course: its class times and its assignments with their subtasks."""

import from .store { AssignmentView, CourseView, MeetingView, TaskView }
import from ..shared.format { format_minutes }
import from .colors { PALETTE }
import from ..shared.styles { BUTTON_DANGER, BUTTON_SMALL, CARD, COURSE_DOT, COURSE_SWATCH }
import from ..shared.ui { CardHeader, TierChip }

glob CHECK_ON: str = "grid h-[17px] w-[17px] flex-none place-items-center rounded-[5px] border-[1.5px] border-ink bg-ink text-[10px] text-white cursor-pointer";
glob CHECK_OFF: str = "grid h-[17px] w-[17px] flex-none place-items-center rounded-[5px] border-[1.5px] border-line-strong bg-surface text-[10px] text-white cursor-pointer";

def:pub TaskLine(task: TaskView, busy: bool, onToggle: Callable[[str, bool], None]) -> JsxElement {
    def handle(e: MouseEvent) {
        onToggle(task.id, not task.done);
    }
    <li className="flex items-center gap-2.5 py-1.5 text-[12.5px]">
        <button
            type="button"
            role="checkbox"
            aria-checked={task.done}
            aria-label={f"{task.title} done"}
            disabled={busy}
            className={CHECK_ON if task.done else CHECK_OFF}
            onClick={handle}
        >
            {"✓" if task.done else ""}
        </button>
        <span className={"min-w-0 flex-1 " + ("text-faint line-through" if task.done else "")}>{task.title}</span>
        <TierChip tier={task.tier} />
        <span className="w-[52px] text-right tabular-nums text-muted">{f"{task.estimated_duration} min"}</span>
    </li>
}

def:pub AssignmentBlock(
    assignment: AssignmentView,
    busy: bool,
    onToggle: Callable[[str, bool], None],
    onRemove: Callable[[str], None]
) -> JsxElement {
    def handle_remove(e: MouseEvent) {
        onRemove(assignment.id);
    }
    progress = f"{assignment.done_count}/{len(assignment.tasks)} done";
    <div className="py-3">
        <div className="flex flex-wrap items-center gap-2">
            <span className="text-[13.5px] font-semibold">{assignment.title}</span>
            {assignment.due_label and <span className="text-[12px] text-muted">{f"due {assignment.due_label}"}</span>}
            <span className="text-[12px] text-faint">{progress}</span>
            <button type="button" className={BUTTON_SMALL + " ml-auto"} disabled={busy} onClick={handle_remove} aria-label={f"Remove {assignment.title}"}>Remove</button>
        </div>
        <ul className="m-0 mt-1.5 list-none p-0">
            {for task in assignment.tasks {
                <TaskLine key={task.id} task={task} busy={busy} onToggle={onToggle} />
            }}
        </ul>
    </div>
}

def:pub MeetingLine(meeting: MeetingView, busy: bool, onRemove: Callable[[str], None]) -> JsxElement {
    def handle_remove(e: MouseEvent) {
        onRemove(meeting.id);
    }
    <li className="flex items-center gap-2.5 py-1.5 text-[12.5px]">
        <span className="font-semibold">{meeting.kind}</span>
        <span className="text-muted">{meeting.summary}</span>
        <button type="button" className={BUTTON_SMALL + " ml-auto"} disabled={busy} onClick={handle_remove} aria-label={f"Remove {meeting.kind}"}>Remove</button>
    </li>
}

"""The names a course goes by in calendar events, beyond its code and name."""
def:pub CourseTags(course: CourseView, busy: bool, onSetTags: Callable[[str, list[str]], None]) -> JsxElement {
    has draft: str = "";

    def addTag(e: FormEvent) {
        e.preventDefault();
        tag = " ".join(draft.split());
        if tag {
            onSetTags(course.id, course.tags + [tag]);
            draft = "";
        }
    }

    known = [course.code] + ([course.name] if course.name else []) + course.tags;
    <div className="mt-4">
        <div className="text-[11px] font-[650] uppercase tracking-[.08em] text-faint">Calendar names</div>
        <p className="mt-1 mb-2 text-[11.5px] text-muted">{"Google events whose names include " + ", ".join(known) + " are labelled " + course.code + "."}</p>
        <div className="flex flex-wrap items-center gap-1.5">
            {for tag in course.tags {
                <span key={tag} className="inline-flex items-center gap-1 rounded-full border border-line bg-canvas py-0.5 pr-1 pl-2.5 text-[11.5px] font-semibold text-body">
                    {tag}
                    <button
                        type="button"
                        disabled={busy}
                        aria-label={f"Remove {tag}"}
                        className="grid h-5 w-5 place-items-center rounded-full text-muted hover:bg-line"
                        onClick={lambda { onSetTags(course.id, [t for t in course.tags if t != tag]); }}
                    >
                        ×
                    </button>
                </span>
            }}
            <form className="flex items-center gap-1.5" onSubmit={addTag} aria-label={f"Add a calendar name for {course.code}"}>
                <input
                    className="w-[150px] rounded-sm border border-line-strong bg-surface px-2 py-1 text-[16px] desk:text-[12px]"
                    placeholder="e.g. ML, Wiens"
                    aria-label={f"Calendar name for {course.code}"}
                    value={draft}
                    onChange={lambda (e: ChangeEvent) { draft = e.target.value; }}
                />
                <button type="submit" className={BUTTON_SMALL} disabled={busy}>Add name</button>
            </form>
        </div>
    </div>
}

def:pub CourseColor(course: CourseView, busy: bool, onSetColor: Callable[[str, str], None]) -> JsxElement {
    <div className="mt-4">
        <div className="text-[11px] font-[650] uppercase tracking-[.08em] text-faint">Color</div>
        <div className="mt-2 flex flex-wrap gap-2" role="radiogroup" aria-label={f"Color for {course.code}"}>
            {for color in PALETTE {
                <button
                    key={color}
                    type="button"
                    role="radio"
                    aria-checked={course.color == color}
                    aria-label={color}
                    disabled={busy}
                    className={"rounded-full p-0.5 ring-offset-2 " + ("ring-2 ring-ink" if course.color == color else "ring-0")}
                    onClick={lambda { onSetColor(course.id, color); }}
                >
                    <span className={"block " + COURSE_SWATCH[color]}></span>
                </button>
            }}
        </div>
    </div>
}

"""Event names tied to this course by hand from the Today calendar."""
def:pub LinkedEvents(course: CourseView, busy: bool, onUnlink: Callable[[str], None]) -> JsxElement {
    if len(course.linked_events) == 0 {
        return <></>;
    }
    <div className="mt-4">
        <div className="text-[11px] font-[650] uppercase tracking-[.08em] text-faint">Linked events</div>
        <ul className="m-0 mt-1 list-none p-0">
            {for title in course.linked_events {
                <li key={title} className="flex items-center gap-2 py-1 text-[12.5px]">
                    <span className="min-w-0 flex-1 truncate">{title}</span>
                    <button type="button" className={BUTTON_SMALL} disabled={busy} onClick={lambda { onUnlink(title); }} aria-label={f"Unlink {title}"}>Unlink</button>
                </li>
            }}
        </ul>
    </div>
}

def:pub CourseCard(
    course: CourseView,
    busy: bool,
    adding: bool,
    onAddTime: Callable[[str], None],
    onSetTags: Callable[[str, list[str]], None],
    onSetColor: Callable[[str, str], None],
    onUnlink: Callable[[str], None],
    onRemoveCourse: Callable[[str], None],
    onRemoveMeeting: Callable[[str], None],
    onRemoveAssignment: Callable[[str], None],
    onToggleTask: Callable[[str, bool], None],
    children: any = None
) -> JsxElement {
    heading = "course-" + course.id;
    load = f"{course.open_tasks} open · {format_minutes(course.open_minutes)}" if course.open_tasks else "All caught up";
    <section className={CARD} aria-labelledby={heading}>
        <CardHeader title={course.code + (f" · {course.name}" if course.name else "")} titleId={heading} aside={load}>
            <span className={COURSE_DOT.get(course.color, "")} aria-hidden="true"></span>
        </CardHeader>
        <div className="px-4 pt-2 pb-4">
            <div className="mt-1 text-[11px] font-[650] uppercase tracking-[.08em] text-faint">Class times</div>
            <ul className="m-0 list-none p-0">
                {if len(course.meetings) == 0 {
                    <li className="py-1.5 text-[12.5px] text-muted">No class times yet. Add lectures and labs so the agent plans around them.</li>
                }}
                {for meeting in course.meetings {
                    <MeetingLine key={meeting.id} meeting={meeting} busy={busy} onRemove={onRemoveMeeting} />
                }}
            </ul>
            {children if adding else <button type="button" className={BUTTON_SMALL + " mt-2"} onClick={lambda (e: MouseEvent) { onAddTime(course.id); }}>Add class time</button>}
            <CourseColor course={course} busy={busy} onSetColor={onSetColor} />
            <CourseTags course={course} busy={busy} onSetTags={onSetTags} />
            <LinkedEvents course={course} busy={busy} onUnlink={onUnlink} />
            <div className="mt-4 text-[11px] font-[650] uppercase tracking-[.08em] text-faint">Assignments</div>
            <div className="divide-y divide-line">
                {if len(course.assignments) == 0 {
                    <p className="m-0 py-2 text-[12.5px] text-muted">None yet. Break one down on the Breakdown screen.</p>
                }}
                {for assignment in course.assignments {
                    <AssignmentBlock key={assignment.id} assignment={assignment} busy={busy} onToggle={onToggleTask} onRemove={onRemoveAssignment} />
                }}
            </div>
            <div className="mt-3 flex justify-end">
                <button type="button" className={BUTTON_DANGER} disabled={busy} onClick={lambda (e: MouseEvent) { onRemoveCourse(course.id); }}>Remove course</button>
            </div>
        </div>
    </section>
}
