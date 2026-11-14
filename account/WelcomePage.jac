"""How CourseCrusher works: shown right after signup, and from Settings any time."""

import from "@jac/runtime" { Link }
import from ..shared.styles { BUTTON, BUTTON_GHOST, BUTTON_PRIMARY, CARD }
import from ..shared.ui { TierChip }

obj WelcomeStep {
    has title: str;
    has detail: str;
    has where: str;
    has path: str;
}

glob STEPS: list[WelcomeStep] = [
    WelcomeStep(
        title="Add your courses and class times",
        detail="Classes become fixed blocks, so nothing is ever planned on top of them.",
        where="Courses",
        path="/courses"
    ),
    WelcomeStep(
        title="Break down an assignment",
        detail="Paste the instructions. The AI splits them into concrete subtasks with a tier and a time estimate. Edit or drop any of them before saving.",
        where="Breakdown",
        path="/breakdown"
    ),
    WelcomeStep(
        title="Approve where it fits",
        detail="You see exactly when each subtask would happen, between your classes and protected hours. Nothing goes on your schedule until you approve it.",
        where="Breakdown",
        path="/breakdown"
    ),
    WelcomeStep(
        title="Work from Today",
        detail="Up next tells you what to do now and why. Start the focus timer, or use Reschedule, Not today and Mark done. Plan shows the next seven days.",
        where="Today",
        path="/"
    ),
    WelcomeStep(
        title="Tell it how much energy you have",
        detail="The Energy menu in the top bar re-plans the rest of today: lower energy keeps heavy Deep Work for later and moves lighter tasks up.",
        where="Top bar",
        path="/"
    ),
    WelcomeStep(
        title="Connect your calendar (optional)",
        detail="Google Calendar events are planned around automatically. Set your working hours and protected time in Settings.",
        where="Connections",
        path="/connections"
    )
];

glob TIERS: list[tuple[str, str]] = [
    ("Deep Work", "Sustained focus: coding, problem sets, real writing. Kept off late nights."),
    ("Shallow Work", "Needs attention but not deep focus: formatting, routine edits, admin."),
    ("Low Energy", "Quick and easy: a submission, light review, a short reading.")
];

def:pub WelcomePage -> JsxElement {
    <div className="mx-auto flex max-w-[760px] flex-col gap-[13px]">
        <section className={CARD + " px-5 py-5 desk:px-6"} aria-labelledby="welcome-h">
            <h2 id="welcome-h" className="m-0 text-[19px] font-[650] tracking-[-0.3px]">Welcome to CourseCrusher</h2>
            <p className="mt-2 mb-0 text-[13.5px] leading-[1.55] text-body">
                Paste an assignment, get it broken into small steps, and let the planner fit them into the free time between your classes. Here's how it works.
            </p>
            <ol className="m-0 mt-4 flex list-none flex-col gap-3 p-0">
                {for (index, step) in enumerate(STEPS) {
                    <li key={step.title} className="flex gap-3">
                        <span className="grid h-7 w-7 flex-none place-items-center rounded-full bg-ink text-[12px] font-bold text-white" aria-hidden="true">{f"{index + 1}"}</span>
                        <div className="min-w-0">
                            <div className="text-[13.5px] font-[650] tracking-[-0.1px]">
                                {step.title}
                                <Link to={step.path} className="ml-2 text-[11.5px] font-semibold text-brand no-underline">{step.where + " →"}</Link>
                            </div>
                            <p className="mt-1 mb-0 text-[12.5px] leading-[1.5] text-muted">{step.detail}</p>
                        </div>
                    </li>
                }}
            </ol>
        </section>
        <section className={CARD + " px-5 py-4 desk:px-6"} aria-labelledby="tiers-h">
            <h3 id="tiers-h" className="m-0 text-[13.5px] font-[650]">The three kinds of work</h3>
            <ul className="m-0 mt-2.5 flex list-none flex-col gap-2 p-0">
                {for (tier, meaning) in TIERS {
                    <li key={tier} className="flex flex-wrap items-center gap-2 text-[12.5px] text-muted">
                        <TierChip tier={tier} />
                        <span>{meaning}</span>
                    </li>
                }}
            </ul>
        </section>
        <div className="flex flex-wrap items-center gap-2.5">
            <Link to="/courses" className={BUTTON_PRIMARY + " no-underline"}>Add your courses</Link>
            <Link to="/breakdown" className={BUTTON + " no-underline"}>Break down an assignment</Link>
            <Link to="/" className={BUTTON_GHOST + " no-underline"}>Skip to Today</Link>
        </div>
    </div>
}
