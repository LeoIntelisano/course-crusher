"""Breakdown: paste an assignment, review the agent's subtasks, see where they fit, add them to the plan.

Nothing is scheduled until the student presses "Add N to plan".
"""

import from "@jac/runtime" { Link }
import from ..connectors.canvas_assignments { CanvasAssignmentDraft }
import from ..connectors.canvas_preview { list_canvas_samples }
import from .BreakdownCards { ChecksCard, FitCard, SubtaskRow, when_labels }
import from .drafts { DraftRow, default_title, included_rows, retier_row, retime_row, retitle_row, summary, toggle_row }
import from .store { CourseResult, CourseView, SubtaskDraft, add_assignment, add_course, list_courses }
import from ..breakdown { BreakdownResult, Subtask, break_down_assignment }
import from ..planner.fit { FitPreview }
import from ..planner.service { FitResult, preview_fit }
import from ..shell.PlannerContext { usePlanner }
import from ..shared.errors { error_message }
import from ..shared.styles { BUTTON, BUTTON_PRIMARY, CARD, CARD_STACK, COLUMNS, FIELD, HINT, LABEL, TEXTAREA }
import from ..shared.ui { CardHeader, Notice }

def:pub BreakdownPage -> JsxElement {
    ctx: any = usePlanner();
    has courses: list[CourseView] = [];
    has course_id: str = "";
    has new_code: str = "";
    has title: str = "";
    has due_at: str = "";
    has description: str = "";
    has rows: list[DraftRow] = [];
    has source: str = "";
    has editing: bool = False;
    has preview: FitPreview | None = None;
    has breaking: bool = False;
    has saving: bool = False;
    has failure: str = "";
    has notice: str = "";
    has fit_request: int = 0;

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

    async def loadCourses -> None;
    async def createCourse -> None;
    async def breakDown -> None;
    async def refreshFit(next_rows: list[DraftRow]) -> None;
    async def addToPlan -> None;

    def toggle(index: int) {
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

    def finishEditing(e: MouseEvent) {
        editing = not editing;
        if not editing {
            refreshFit(rows);
        }
    }

    async can with entry {
        await loadCourses();
    }

    chosen = [c for c in courses if c.id == course_id];
    course_code = chosen[0].code if chosen else "";
    labels = when_labels(rows, preview);
    adding = len(included_rows(rows));

    <div className={COLUMNS}>
        <div className={CARD_STACK}>
            <Notice tone="success" message={notice} />
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
                    {if len(courses) == 0 {
                        <div>
                            <label className={LABEL} htmlFor="new-course">Course</label>
                            <div className="flex gap-2">
                                <input
                                    id="new-course"
                                    className={FIELD}
                                    placeholder="e.g. EECS 445"
                                    value={new_code}
                                    onChange={lambda (e: ChangeEvent) { new_code = e.target.value; }}
                                />
                                <button type="button" className={BUTTON + " mt-[7px] whitespace-nowrap"} onClick={lambda (e: MouseEvent) { createCourse(); }}>Add course</button>
                            </div>
                            <p className={HINT}>You can preview a breakdown first. Add a course before saving it to your plan.</p>
                        </div>
                    } else {
                        <div className="grid grid-cols-1 gap-4 desk:grid-cols-3">
                            <div>
                                <label className={LABEL} htmlFor="bd-course">Course</label>
                                <select id="bd-course" className={FIELD} value={course_id} onChange={lambda (e: ChangeEvent) { course_id = e.target.value; }}>
                                    {for course in courses { <option key={course.id} value={course.id}>{course.code}</option> }}
                                </select>
                            </div>
                            <div>
                                <label className={LABEL} htmlFor="bd-title">Title</label>
                                <input id="bd-title" className={FIELD} placeholder="Project 2" value={title} onChange={lambda (e: ChangeEvent) { title = e.target.value; }} />
                            </div>
                            <div>
                                <label className={LABEL} htmlFor="bd-due">Due</label>
                                <input id="bd-due" type="datetime-local" className={FIELD} value={due_at} onChange={lambda (e: ChangeEvent) { due_at = e.target.value; }} />
                            </div>
                        </div>
                    }}
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
                        <span className="hidden text-[11.5px] text-faint desk:inline">⌘/Ctrl + Enter</span>
                    </div>
                </form>
            </section>

            {if len(rows) > 0 {
                <section className={CARD} aria-labelledby="bd">
                    <div className="border-b border-line px-3.5 py-3 desk:px-4 desk:py-3.5">
                        <div className="text-[11px] font-[650] uppercase tracking-[.08em] text-faint">{f"Source · Reviewed · {course_code}"}</div>
                        <p className="mt-2 mb-0 line-clamp-4 border-l-2 border-line-strong pl-[11px] text-[12.5px] leading-[1.55] text-body whitespace-pre-line">{source}</p>
                    </div>
                    <div className="flex items-center gap-2.5 px-4 pt-3">
                        <h2 id="bd" className="m-0 text-[13.5px] font-[650] tracking-[-0.1px] desk:text-[13px]" aria-live="polite">{"Agent breakdown — " + summary(rows)}</h2>
                    </div>
                    <div className="divide-y divide-line" aria-busy={"true" if breaking else "false"}>
                        {for (index, row) in enumerate(rows) {
                            <SubtaskRow
                                key={f"{index}"}
                                row={row}
                                index={index}
                                when={labels[index]}
                                editing={editing}
                                onToggle={toggle}
                                onTitle={lambda (i: int, value: str) { rows = retitle_row(rows, i, value); }}
                                onTier={lambda (i: int, value: str) { rows = retier_row(rows, i, value); }}
                                onMinutes={lambda (i: int, value: str) { rows = retime_row(rows, i, value); }}
                            />
                        }}
                    </div>
                    <div className="flex flex-wrap items-center gap-2.5 rounded-b-lg border-t border-line bg-canvas px-4 py-[13px]">
                        <p className="order-first mb-1 basis-full text-[11.5px] text-muted desk:order-last desk:mb-0 desk:ml-auto desk:basis-auto desk:text-right">
                            Nothing is scheduled until you confirm.<br />Every slot stays editable.
                        </p>
                        <button type="button" className={BUTTON_PRIMARY} disabled={saving or adding == 0} onClick={lambda (e: MouseEvent) { addToPlan(); }}>
                            {"Adding…" if saving else f"Add {adding} to plan"}
                        </button>
                        <button type="button" className={BUTTON} onClick={finishEditing}>{"Done editing" if editing else "Edit subtasks"}</button>
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
