"""The planning assistant: answers a student's schedule questions from their own plan.

Read-only. The model sees a plain-text brief of the plan the Today and Plan
screens show (built by `plan_brief`, which is pure), and the last few turns of
the conversation. It never changes anything; it points at the button that does.
"""

import logging;
import os;
import sys;
import from datetime { datetime, timezone }
import from breakdown { LLM_FIXTURE_ENV, BREAKDOWNS_PER_HOUR, FIXTURE_REPEATS, consume_quota, ensure_usage }
import from planner.inputs { PlanningInputs, load_inputs }
import from planner.views { WeekView, week_view }
import from shared.ai { current_ai_status, failure_message }
import from shared.timefmt { clock_label, clock_text, date_label }

glob logger: logging.Logger = logging.getLogger("course_crusher.assistant");
glob MAX_QUESTION_CHARS: int = 1000;
glob MAX_TURN_CHARS: int = 2000;
glob MAX_HISTORY_TURNS: int = 6;
glob ASSISTANT_UNAVAILABLE: str = "The assistant isn't available right now. Try again in a minute.";
glob FIXTURE_ANSWER: str = "Demo mode: the assistant is answering with canned text. Set an API key to get real answers about your plan.";
glob ROLES: set[str] = {"student", "assistant"};

"""One message in the chat panel. `role` is "student" or "assistant"."""
obj ChatTurn {
    has role: str;
    has text: str;
}

obj AssistantReply {
    has ok: bool;
    has error: str = "";
    has answer: str = "";
}

def answer_planning_question(question: str, plan: str, conversation: str) -> str by llm(
    temperature=0.3,
    system_prompt=
    """You are CourseCrusher's planning assistant for a college student.
    Answer questions about their schedule using only the plan you are given.
    Be brief: at most four short sentences, or a short list.
    Name times, tasks, courses and deadlines exactly as the plan shows them.
    You cannot change the schedule. When the student wants a change, say which control does it:
    Reschedule, Swap task, Not today or Mark done on Today; the check mark on Plan;
    the Energy menu in the top bar; working hours and protected time in Settings;
    new assignments in Breakdown; class times in Courses.
    If the plan doesn't answer the question, say so. Never invent tasks, events or deadlines.
    Politely decline requests that aren't about planning or studying."""
);
sem answer_planning_question = "Answer one planning question from the student's current plan.";
sem answer_planning_question.question = "The student's question.";
sem answer_planning_question.plan = "The student's plan right now: working hours, energy, each day's blocks and events, and work that doesn't fit.";
sem answer_planning_question.conversation = "Earlier messages in this chat, oldest first. May be empty.";

def day_lines(week: WeekView) -> list[str] {
    lines: list[str] = [];
    for day in week.days {
        heading = f"{day.day_label}, {day.date_label}" if day.day_label in ["Today", "Tomorrow"] else day.date_label;
        items = [
            f"  - {item.range_label}: {item.tier} · {item.title} ({item.course_code} · {item.assignment_title}"
            + (f", due {item.due_label}" if item.due_label else "")
            + (", lands after the deadline" if item.late else "")
            + ")"
            for item in day.items
        ];
        events = [f"  - {event.detail.split(' · ')[0]}: {event.title} (fixed)" for event in day.events];
        body = items + events if items or events else ["  - nothing planned"];
        lines = lines + [heading + ":"] + body;
    }
    return lines;
}

def unplaced_lines(week: WeekView) -> list[str] {
    if not week.unplaced {
        return [];
    }
    return ["Doesn't fit in the next week:"] + [
        f"  - {item.title} ({item.course_code} · {item.assignment_title}, {item.minutes} min"
        + (f", due {item.due_label}" if item.due_label else "")
        + ")"
        for item in week.unplaced
    ];
}

"""The plan as the model sees it: the same facts as the Plan screen, as text."""
def plan_brief(inputs: PlanningInputs, now: datetime) -> str {
    rules = inputs.rules;
    local_now = now.astimezone(rules.zone);
    week = week_view(inputs, now);
    header = [
        f"Now: {date_label(local_now.date())}, {clock_label(local_now)} ({rules.zone}).",
        f"Energy: {rules.energy}.",
        f"Working hours {clock_text(rules.day_start)}-{clock_text(rules.day_end)}; Deep Work ends by {clock_text(rules.deep_work_cutoff)}.",
        f"Open subtasks: {len(inputs.tasks)}. Deadlines at risk: {week.at_risk}."
    ];
    protected = [f"Protected every day: {p.label} {clock_text(p.start)}-{clock_text(p.end)}." for p in inputs.protected];
    return "\n".join(header + protected + day_lines(week) + unplaced_lines(week));
}

"""Earlier turns as text, newest last, each clipped so a long paste can't crowd out the plan."""
def conversation_text(history: list[ChatTurn]) -> str {
    recent = [turn for turn in history if turn.role in ROLES and turn.text.strip()][-MAX_HISTORY_TURNS:];
    return "\n".join([
        f"{'Student' if turn.role == 'student' else 'Assistant'}: {turn.text.strip()[:MAX_TURN_CHARS]}"
        for turn in recent
    ]);
}

def assistant_failure(err: Exception) -> str {
    status = current_ai_status(LLM_FIXTURE_ENV);
    if not status.ready {
        return status.message;
    }
    return failure_message(err, ASSISTANT_UNAVAILABLE);
}

"""Ask the assistant about your plan. Shares the breakdown's hourly limit."""
def:protect ask_planner(question: str, history: list[ChatTurn]) -> AssistantReply {
    asked = question.strip();
    if not asked {
        return AssistantReply(ok=False, error="Type a question first.");
    }
    if len(asked) > MAX_QUESTION_CHARS {
        return AssistantReply(ok=False, error=f"Keep questions under {MAX_QUESTION_CHARS} characters.");
    }
    if not consume_quota(ensure_usage(), datetime.now(timezone.utc)) {
        return AssistantReply(
            ok=False, error=f"You've used {BREAKDOWNS_PER_HOUR} AI requests this hour. Try again later."
        );
    }
    now = datetime.now(timezone.utc);
    return assistant_reply(asked, plan_brief(load_inputs(now), now), conversation_text(history));
}

def assistant_reply(question: str, plan: str, conversation: str) -> AssistantReply {
    try {
        answer = answer_planning_question(question, plan, conversation);
    } except Exception as err {
        logger.exception("Assistant model call failed (%s)", type(err).__name__);
        return AssistantReply(ok=False, error=assistant_failure(err));
    }
    text = str(answer).strip();
    if not text {
        return AssistantReply(ok=False, error=ASSISTANT_UNAVAILABLE);
    }
    return AssistantReply(ok=True, answer=text);
}

"""End-to-end runs without an API key: answer every question with canned text."""
def install_fixture_answers {
    import from jaclang.byllm.lib { MockLLM }
    setattr(
        sys.modules[answer_planning_question.__module__],
        "llm",
        MockLLM(outputs=[FIXTURE_ANSWER] * FIXTURE_REPEATS)
    );
}

with entry {
    if os.environ.get(LLM_FIXTURE_ENV) {
        install_fixture_answers();
    }
}
