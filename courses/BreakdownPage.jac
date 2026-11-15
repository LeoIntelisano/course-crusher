"""Breakdown: paste an assignment, review the agent's subtasks, see where they fit, approve the times.
Nothing is scheduled until the student reviews the proposed slots and presses
"Approve schedule"; the approved times are saved with each subtask.
Until then, the draft is kept in the planner context, so visiting another
screen doesn't lose it.
"""

import from "@jac/runtime" { Link }
import from ..connectors.canvas_assignments { CanvasAssignmentDraft }
import from ..connectors.canvas_preview { list_canvas_samples }
import from .BreakdownCards {
    ChecksCard,
    FitCard,
    ScheduleReview,
    SubtaskRow,
    approved_starts,
    proposed_starts,
    when_labels
}
import from .drafts {
    BreakdownDraft,
    DraftRow,
    add_blank_row,
    course_to_select,
    default_title,
    included_rows,
    invalid_schedule_row,
    manual_starts,
    auto_schedule_row,
    set_date_from_suggestion,
    set_time_from_suggestion,
    is_blank,
    retier_row,
    retime_row,
    retitle_row,
    summary,
    toggle_row
}
import from .store { CourseResult, CourseView, SubtaskDraft, add_assignment, add_course, list_courses }
import from ..breakdown { BreakdownResult, Subtask, ai_status, break_down_assignment }
import from ..shared.ai { AiStatus }
import from ..planner.fit { FitPreview }
import from ..planner.service { FitResult, preview_fit }
import from ..shell.PlannerContext { usePlanner }
import from ..shared.errors { error_message }
import from ..shared.styles { BUTTON, BUTTON_GHOST, BUTTON_PRIMARY, CARD, CARD_STACK, COLUMNS, FIELD, HINT, LABEL, TEXTAREA }
import from ..shared.ui { CardHeader, Notice }

glob LINK_BUTTON: str = "cursor-pointer border-0 bg-transparent p-0 text-[12px] font-semibold text-brand hover:underline";

def:pub BreakdownPage -> JsxElement {
    ctx: any = usePlanner();
    has courses: list[CourseView] = [];
    has course_id: str = "";
    has new_code: str = "";
    has adding_course: bool = False;
    has restored: bool = False;
    has title: str = "";
    has due_at: str = "";
    has description: str = "";
    has rows: list[DraftRow] = [];
    has source: str = "";
    has editing: bool = False;
    has reviewing: bool = False;
    has preview: FitPreview | None = None;
    has breaking: bool = False;
    has saving: bool = False;
    has failure: str = "";
    has notice: str = "";
    has fit_request: int = 0;

    has ai: AiStatus | None = None;
    has from_ai: bool = False;
    has samples: list[CanvasAssignmentDraft] = [];
    has loading_samples: bool = False;

    async def loadSamples -> None {
        loading_samples = True;
        try {
            samples = await list_canvas_samples();
            failure = "";
        } except Exception as err {
            failure = error_message(err);
        }
        loading_samples = False;
    }

    def selectSample(value: str) -> None {
        for sample in samples {
            if sample.source_assignment_id == value {
                title = sample.title;
                description = sample.description;
                due_at = sample.due_at;
                rows = [];
                source = "";
                preview = None;
                fit_request = fit_request + 1;
                editing = False;
                failure = "";
                notice = "Sample loaded. Review the course and due date in your profile timezone before breaking it down.";
                if sample.needs_description {
                    notice = "This sample has no description. Add instructions before breaking it down.";
                }
            }
        }
    }

    async def loadAiStatus -> None {
        try {
            ai = await ai_status();
        } except Exception {
            # The status is advisory; a real breakdown attempt still reports its own error.
            ai = None;
        }
    }

    def addByHand -> None {
        if len(rows) == 0 {
            source = description.strip();
            preview = None;
            from_ai = False;
        }
        rows = add_blank_row(rows);
        editing = True;
        failure = "";
    }

    def currentDraft -> BreakdownDraft {
        return BreakdownDraft(course_id=course_id, title=title, due_at=due_at, description=description, source=source, rows=rows);
    }

    def restoreDraft -> None;
    def discardDraft -> None;
    async def loadCourses -> None;
    async def createCourse -> None;
    async def breakDown -> None;
    async def refreshFit(next_rows: list[DraftRow]) -> None;
    async def addToPlan -> None;

    async def startReview -> None {
        editing = False;
        await refreshFit(rows);
        if preview is not None {
            reviewing = True;
        }
    }

    def toggle(index: int) {
        if reviewing {
            return;
        }
        next_rows = toggle_row(rows, index);
        rows = next_rows;
        refreshFit(next_rows);
    }

    def onKeys(e: KeyboardEvent) {
        if e.key == "Enter" and (e.metaKey or e.ctrlKey) {
            e.preventDefault();
            breakDown();
        }
    }

    # Enter here adds the course instead of submitting the form (a breakdown).
    def onCourseKeys(e: KeyboardEvent) {
        if e.key == "Enter" {
            e.preventDefault();
            createCourse();
        }
    }

    def finishEditing(e: MouseEvent) {
        editing = not editing;
        if not editing {
            refreshFit(rows);
        }
    }

    # Declared before the mount effect so the first render can't overwrite the kept draft.
    can with (course_id, title, due_at, description, source, rows) entry {
        if restored {
            ctx.keepBreakdownDraft(currentDraft());
        }
    }

    async can with entry {
        restoreDraft();
        await loadCourses();
        await loadAiStatus();
        if len(rows) > 0 {
            await refreshFit(rows);
        }
    }
    chosen = [c for c in courses if c.id == course_id];
    course_code = chosen[0].code if chosen else "";
    labels = when_labels(rows, preview);
    suggestions = proposed_starts(rows, preview);
    adding = len(included_rows(rows));
    has_courses = len(courses) > 0;
    blank = is_blank(currentDraft());

    <div className={COLUMNS}>
        <div className={CARD_STACK}>
            <Notice tone="success" message={notice} />
            {if ai is not None and not ai.ready {
                <Notice tone="info" message={ai.message + " You can still add subtasks by hand."} />
            }}
            <section className={CARD} aria-labelledby="compose-h">
                <CardHeader title="Break down a new assignment" titleId="compose-h" aside="AI" />
                <form
                    className="flex flex-col gap-4 px-3.5 pt-3 pb-3.5 desk:px-4 desk:pb-4"
                    onSubmit={lambda (e: FormEvent) { e.preventDefault(); breakDown(); }}
                    noValidate={True}
                >
                    <div>
                        <button type="button" className={BUTTON} disabled={loading_samples or breaking or saving} onClick={lambda (e: MouseEvent) { loadSamples(); }}>
                            {"Loading samples..." if loading_samples else "Load Canvas samples"}
                        </button>
                        <p className={HINT}>Example data only. Choose a sample and review it before breaking it down. Canvas is not connected.</p>
                        {if samples {
                            <label className={LABEL} htmlFor="canvas-sample">Sample assignment</label>
                            <select id="canvas-sample" className={FIELD} value="" disabled={breaking or saving} onChange={lambda (e: ChangeEvent) { selectSample(e.target.value); }}>
                                <option value="">Choose a sample to load</option>
                                {for sample in samples { <option key={sample.source_assignment_id} value={sample.source_assignment_id}>{sample.title}</option> }}
                            </select>
                        }}
                    </div>
                    {if adding_course or not has_courses {
                        <div>
                            <label className={LABEL} htmlFor="new-course">{"New course" if has_courses else "Course"}</label>
                            <div className="flex gap-2">
                                <input
                                    id="new-course"
                                    className={FIELD}
                                    placeholder="e.g. EECS 445"
                                    value={new_code}
                                    onChange={lambda (e: ChangeEvent) { new_code = e.target.value; }}
                                    onKeyDown={onCourseKeys}
                                    autoFocus={adding_course}
                                />
                                <button type="button" className={BUTTON + " mt-[7px] whitespace-nowrap"} onClick={lambda (e: MouseEvent) { createCourse(); }}>Add course</button>
                                {if has_courses {
                                    <button type="button" className={BUTTON_GHOST + " mt-[7px]"} onClick={lambda (e: MouseEvent) { adding_course = False; new_code = ""; }}>Cancel</button>
                                }}
                            </div>
                            {if not has_courses {
                                <p className={HINT}>You can preview a breakdown first. Add a course before saving it to your plan.</p>
                            }}
                        </div>
                    }}
                    <div className={"grid grid-cols-1 gap-4 desk:grid-cols-3" if has_courses else "grid grid-cols-1 gap-4 desk:grid-cols-2"}>
                        {if has_courses {
                            <div>
                                <div className="flex items-baseline justify-between gap-2">
                                    <label className={LABEL} htmlFor="bd-course">Course</label>
                                    {if not adding_course {
                                        <button type="button" className={LINK_BUTTON} onClick={lambda (e: MouseEvent) { adding_course = True; }}>+ New course</button>
                                    }}
                                </div>
                                <select id="bd-course" className={FIELD} value={course_id} onChange={lambda (e: ChangeEvent) { course_id = e.target.value; }}>
                                    {for course in courses { <option key={course.id} value={course.id}>{course.code}</option> }}
                                </select>
                            </div>
                        }}
                        <div>
                            <label className={LABEL} htmlFor="bd-title">Title</label>
                            <input id="bd-title" className={FIELD} placeholder="Project 2" value={title} onChange={lambda (e: ChangeEvent) { title = e.target.value; }} />
                        </div>
                        <div>
                            <label className={LABEL} htmlFor="bd-due">Due</label>
                            <input id="bd-due" type="datetime-local" className={FIELD} value={due_at} onChange={lambda (e: ChangeEvent) { due_at = e.target.value; }} />
                        </div>
                    </div>
                    <div>
                        <label className={LABEL} htmlFor="assignment-input">Assignment description</label>
                        <textarea
                            id="assignment-input"
                            rows={5}
                            className={TEXTAREA}
                            placeholder="Paste the instructions from Canvas, e.g. “Lab 4 report: damped pendulum, due Fri 5 PM…”"
                            aria-describedby="assignment-hint assignment-error"
                            aria-invalid={"true" if failure and not description.strip() else None}
                            value={description}
                            onChange={lambda (e: ChangeEvent) { description = e.target.value; failure = ""; }}
                            onKeyDown={onKeys}
                        ></textarea>
                        <p id="assignment-hint" className={HINT}>The agent works only from what you paste. Nothing is scheduled until you confirm.</p>
                        <div id="assignment-error"><Notice tone="error" message={failure} /></div>
                    </div>
                    <div className="flex flex-wrap items-center gap-3">
                        <button type="submit" className={BUTTON_PRIMARY + " min-h-[46px] basis-full desk:basis-auto desk:min-h-0"} disabled={breaking or saving}>
                            {"Breaking down…" if breaking else "Break down assignment"}
                        </button>
                        <button type="button" className={BUTTON + " basis-full desk:basis-auto"} disabled={breaking or saving} onClick={lambda (e: MouseEvent) { addByHand(); }}>
                            Add subtasks by hand
                        </button>
                        <span className="hidden text-[11.5px] text-faint desk:inline">⌘/Ctrl + Enter</span>
                        {if not blank {
                            <button type="button" className={BUTTON_GHOST + " desk:ml-auto"} disabled={breaking or saving} onClick={lambda (e: MouseEvent) { discardDraft(); }}>Discard draft</button>
                        }}
                    </div>
                </form>
            </section>

            {if len(rows) > 0 {
                <section className={CARD} aria-labelledby="bd">
                    {source and <div className="border-b border-line px-3.5 py-3 desk:px-4 desk:py-3.5">
                        <div className="text-[11px] font-[650] uppercase tracking-[.08em] text-faint">
                            {"Source · Reviewed" + (f" · {course_code}" if course_code else "")}
                        </div>
                        <p className="mt-2 mb-0 line-clamp-4 border-l-2 border-line-strong pl-[11px] text-[12.5px] leading-[1.55] text-body whitespace-pre-line">{source}</p>
                    </div>}
                    <div className="flex items-center gap-2.5 px-4 pt-3">
                        <h2 id="bd" className="m-0 text-[13.5px] font-[650] tracking-[-0.1px] desk:text-[13px]" aria-live="polite">{("Agent breakdown — " if from_ai else "Your breakdown — ") + summary(rows)}</h2>
                    </div>
                    <div className="divide-y divide-line" aria-busy={"true" if breaking else "false"}>
                        {for (index, row) in enumerate(rows) {
                            <SubtaskRow
                                key={f"{index}"}
                                row={row}
                                index={index}
                                when={labels[index]}
                                proposed_start={suggestions[index]}
                                editing={editing}
                                onToggle={toggle}
                                onTitle={lambda (i: int, value: str) { rows = retitle_row(rows, i, value); }}
                                onTier={lambda (i: int, value: str) { rows = retier_row(rows, i, value); }}
                                onMinutes={lambda (i: int, value: str) { rows = retime_row(rows, i, value); }}
                                onDate={lambda (i: int, value: str) { rows = set_date_from_suggestion(rows, i, value, suggestions[i]); }}
                                onTime={lambda (i: int, value: str) { rows = set_time_from_suggestion(rows, i, value, suggestions[i]); }}
                                onAuto={lambda (i: int) { rows = auto_schedule_row(rows, i); refreshFit(rows); }}
                            />
                        }}
                    </div>
                    {reviewing and preview is not None and <ScheduleReview preview={preview} />}
                    <div className="flex flex-wrap items-center gap-2.5 rounded-b-lg border-t border-line bg-canvas px-4 py-[13px]">
                        <p className="order-first mb-1 basis-full text-[11.5px] text-muted desk:order-last desk:mb-0 desk:ml-auto desk:basis-auto desk:text-right">
                            Nothing is scheduled until you approve the times.
                        </p>
                        {if reviewing {
                            <button key="approve" type="button" className={BUTTON_PRIMARY} disabled={saving} onClick={lambda (e: MouseEvent) { addToPlan(); }}>
                                {"Saving…" if saving else f"Approve schedule ({adding})"}
                            </button>
                            <button key="back" type="button" className={BUTTON} disabled={saving} onClick={lambda (e: MouseEvent) { reviewing = False; }}>Back to edit</button>
                        } else {
                            <button key="review" type="button" className={BUTTON_PRIMARY} disabled={saving or adding == 0} onClick={lambda (e: MouseEvent) { startReview(); }}>
                                {f"Review schedule for {adding}"}
                            </button>
                            <button key="edit" type="button" className={BUTTON} onClick={finishEditing}>{"Done editing" if editing else "Edit subtasks"}</button>
                            if editing {
                                <button key="add-subtask" type="button" className={BUTTON} onClick={lambda (e: MouseEvent) 
                            { addByHand(); }}>Add subtask</button>
                            }
                        }}
                    </div>
                </section>
            }}
        </div>
        <div className={CARD_STACK}>
            <FitCard preview={preview} />
            <ChecksCard preview={preview} />
            {if notice {
                <Link to="/" className="text-[12.5px] font-semibold text-brand">See it on Today →</Link>
            }}
        </div>
    </div>
}
