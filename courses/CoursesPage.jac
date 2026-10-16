"""Courses: add courses, their weekly class times, and track each assignment's subtasks."""

import from .CourseCard { CourseCard }
import from .store {
    CourseResult,
    CourseView,
    add_course,
    add_meeting,
    list_courses,
    remove_assignment,
    remove_course,
    remove_meeting,
    set_task_done
}
import from ..shell.PlannerContext { usePlanner }
import from ..shared.errors { error_message }
import from ..shared.styles { BUTTON, BUTTON_PRIMARY, CARD, FIELD, LABEL }
import from ..shared.ui { CardHeader, EmptyState, Notice }

glob WEEKDAYS: list[str] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
glob MEETING_KINDS: list[str] = ["Lecture", "Lab", "Discussion", "Office hours", "Seminar"];
glob DAY_ON: str = "min-w-[44px] rounded-sm border border-ink bg-ink px-2 py-1.5 text-[12px] font-semibold text-white";
glob DAY_OFF: str = "min-w-[44px] rounded-sm border border-line-strong bg-surface px-2 py-1.5 text-[12px] font-semibold text-muted";

def:pub CoursesPage -> JsxElement {
    ctx: any = usePlanner();
    has courses: list[CourseView] = [];
    has loaded: bool = False;
    has code: str = "";
    has name: str = "";
    has meeting_course: str = "";
    has meeting_kind: str = "Lecture";
    has meeting_days: list[int] = [];
    has meeting_start: str = "11:00";
    has meeting_end: str = "12:20";
    has meeting_location: str = "";
    has busy: bool = False;
    has failure: str = "";

    async def load -> None;
    async def apply(result: CourseResult | None) -> bool;
    async def createCourse -> None;
    async def createMeeting -> None;
    async def deleteCourse(course_id: str) -> None;
    async def deleteMeeting(meeting_id: str) -> None;
    async def deleteAssignment(assignment_id: str) -> None;
    async def toggleTask(task_id: str, done: bool) -> None;

    def toggleDay(day: int) {
        meeting_days = [d for d in meeting_days if d != day] if day in meeting_days else meeting_days + [day];
    }

    async can with entry {
        await load();
    }

    meeting_form = <form
        className="mt-3 flex flex-col gap-3 rounded-md border border-line bg-canvas p-3"
        onSubmit={lambda (e: FormEvent) { e.preventDefault(); createMeeting(); }}
        noValidate={True}
        aria-label="Add class time"
    >
        <div className="grid grid-cols-1 gap-3 desk:grid-cols-2">
            <div>
                <label className={LABEL} htmlFor="meeting-kind">Type</label>
                <select id="meeting-kind" className={FIELD} value={meeting_kind} onChange={lambda (e: ChangeEvent) { meeting_kind = e.target.value; }}>
                    {for kind in MEETING_KINDS { <option key={kind} value={kind}>{kind}</option> }}
                </select>
            </div>
            <div>
                <label className={LABEL} htmlFor="meeting-location">Where</label>
                <input id="meeting-location" className={FIELD} placeholder="Chrysler 220" value={meeting_location} onChange={lambda (e: ChangeEvent) { meeting_location = e.target.value; }} />
            </div>
            <div>
                <label className={LABEL} htmlFor="meeting-start">Starts</label>
                <input id="meeting-start" type="time" className={FIELD} value={meeting_start} onChange={lambda (e: ChangeEvent) { meeting_start = e.target.value; }} />
            </div>
            <div>
                <label className={LABEL} htmlFor="meeting-end">Ends</label>
                <input id="meeting-end" type="time" className={FIELD} value={meeting_end} onChange={lambda (e: ChangeEvent) { meeting_end = e.target.value; }} />
            </div>
        </div>
        <fieldset className="m-0 border-0 p-0">
            <legend className={LABEL}>Days</legend>
            <div className="mt-[7px] flex flex-wrap gap-1.5">
                {for (index, day) in enumerate(WEEKDAYS) {
                    <button
                        key={day}
                        type="button"
                        aria-pressed={index in meeting_days}
                        className={DAY_ON if index in meeting_days else DAY_OFF}
                        onClick={lambda (e: MouseEvent) { toggleDay(index); }}
                    >
                        {day}
                    </button>
                }}
            </div>
        </fieldset>
        <div className="flex gap-2">
            <button type="submit" className={BUTTON_PRIMARY} disabled={busy}>Save class time</button>
            <button type="button" className={BUTTON} onClick={lambda (e: MouseEvent) { meeting_course = ""; }}>Cancel</button>
        </div>
    </form>;

    <div className="mx-auto flex max-w-[860px] flex-col gap-[13px]">
        <Notice tone="error" message={failure} />
        <section className={CARD} aria-labelledby="add-course-h">
            <CardHeader title="Add a course" titleId="add-course-h" />
            <form
                className="grid grid-cols-1 items-end gap-3 px-4 pt-3 pb-4 desk:grid-cols-[160px_1fr_auto]"
                onSubmit={lambda (e: FormEvent) { e.preventDefault(); createCourse(); }}
                noValidate={True}
            >
                <div>
                    <label className={LABEL} htmlFor="course-code">Code</label>
                    <input id="course-code" className={FIELD} placeholder="EECS 445" value={code} onChange={lambda (e: ChangeEvent) { code = e.target.value; }} />
                </div>
                <div>
                    <label className={LABEL} htmlFor="course-name">Name (optional)</label>
                    <input id="course-name" className={FIELD} placeholder="Machine Learning" value={name} onChange={lambda (e: ChangeEvent) { name = e.target.value; }} />
                </div>
                <button type="submit" className={BUTTON_PRIMARY + " min-h-[42px]"} disabled={busy}>Add course</button>
            </form>
        </section>
        {if loaded and len(courses) == 0 {
            <section className={CARD}>
                <EmptyState title="No courses yet" detail="Add each class you're taking, with its lecture and lab times." />
            </section>
        }}
        {for course in courses {
            <CourseCard
                key={course.id}
                course={course}
                busy={busy}
                adding={meeting_course == course.id}
                onAddTime={lambda (course_id: str) { meeting_course = course_id; meeting_days = []; }}
                onRemoveCourse={deleteCourse}
                onRemoveMeeting={deleteMeeting}
                onRemoveAssignment={deleteAssignment}
                onToggleTask={toggleTask}
            >
                {meeting_form}
            </CourseCard>
        }}
    </div>
}
