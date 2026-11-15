"""The planning assistant: an Ask button on every signed-in screen and a compact chat panel.

Answers come from the student's own plan and change nothing, so the panel never
refreshes the plan. The conversation lives only in this component.
"""

import from "react" { useRef }
import from ..planner.assistant { AssistantReply, ChatTurn, ask_planner }
import from ..shared.errors { error_message }
import from ..shared.styles { BUTTON_PRIMARY, FIELD_INLINE }
import from ..shared.ui { Notice }

glob SUGGESTIONS: list[str] = [
    "What should I work on next?",
    "Can I fit everything due this week?",
    "What's due in the next few days?",
    "Why is my next task scheduled then?"
];
glob BUBBLE_STUDENT: str = "ml-8 self-end whitespace-pre-line rounded-lg rounded-br-sm bg-ink px-3 py-2 text-[13px] leading-[1.45] text-white";
glob BUBBLE_ASSISTANT: str = "mr-8 self-start whitespace-pre-line rounded-lg rounded-bl-sm border border-line bg-canvas px-3 py-2 text-[13px] leading-[1.45] text-text";
glob SUGGESTION: str = "rounded-full border border-line-strong bg-surface px-3 py-1.5 text-left text-[12px] font-semibold text-body cursor-pointer hover:border-ink disabled:opacity-60";

def:pub AssistantPanel -> JsxElement {
    has open: bool = False;
    has turns: list[ChatTurn] = [];
    has draft: str = "";
    has sending: bool = False;
    has failure: str = "";
    listRef = useRef(None);

    async def askQuestion(question: str) -> None {
        text = question.strip();
        if not text or sending {
            return;
        }
        history = turns;
        asked = history + [ChatTurn(role="student", text=text)];
        turns = asked;
        draft = "";
        failure = "";
        sending = True;
        reply: AssistantReply | None = None;
        try {
            reply = await ask_planner(text, history);
        } except Exception as err {
            failure = error_message(err);
            sending = False;
            return;
        }
        sending = False;
        if reply is None or not reply.ok {
            failure = reply.error if reply else "The assistant didn't answer.";
            return;
        }
        turns = asked + [ChatTurn(role="assistant", text=reply.answer)];
    }

    def onKeys(e: KeyboardEvent) {
        if e.key == "Escape" {
            open = False;
        }
    }

    def onInputKeys(e: KeyboardEvent) {
        if e.key == "Enter" and not e.shiftKey {
            e.preventDefault();
            askQuestion(draft);
        }
    }

    can with [turns, sending] entry {
        box: any = listRef.current;
        if box {
            box.scrollTop = box.scrollHeight;  # jac:ignore[W2001]
        }
    }

    <>
        {open and <section
            role="dialog"
            aria-label="Planning assistant"
            onKeyDown={onKeys}
            className="fixed inset-x-3 top-[64px] bottom-[136px] z-30 flex flex-col rounded-lg border border-line bg-surface shadow-[0_12px_40px_rgba(18,21,26,0.18)] desk:inset-auto desk:right-6 desk:bottom-[84px] desk:h-[520px] desk:w-[380px]"
        >
            <div className="flex items-center gap-2.5 border-b border-line px-4 py-3">
                <span className="grid h-[22px] w-[22px] place-items-center rounded-md bg-brand text-[12px] font-bold text-white" aria-hidden="true">✦</span>
                <h2 className="m-0 text-[13.5px] font-[650] tracking-[-0.1px]">Planning assistant</h2>
                <button
                    type="button"
                    aria-label="Close the assistant"
                    className="ml-auto grid h-8 w-8 place-items-center rounded-sm border-0 bg-transparent text-[16px] text-muted cursor-pointer hover:bg-canvas"
                    onClick={lambda (e: MouseEvent) { open = False; }}
                >
                    ×
                </button>
            </div>
            <div ref={listRef} className="flex flex-1 flex-col gap-2.5 overflow-y-auto px-4 py-3" aria-live="polite" aria-busy={"true" if sending else "false"}>
                {if len(turns) == 0 {
                    <div className="flex flex-col gap-2.5">
                        <p className="m-0 text-[12.5px] leading-[1.5] text-muted">
                            Ask about your schedule. Answers come from your current plan; nothing changes until you use the buttons on Today and Plan.
                        </p>
                        <div className="flex flex-wrap gap-2">
                            {for suggestion in SUGGESTIONS {
                                <button key={suggestion} type="button" className={SUGGESTION} disabled={sending} onClick={lambda (e: MouseEvent) { askQuestion(suggestion); }}>
                                    {suggestion}
                                </button>
                            }}
                        </div>
                    </div>
                }}
                {for (index, turn) in enumerate(turns) {
                    <div key={f"{index}"} className={BUBBLE_STUDENT if turn.role == "student" else BUBBLE_ASSISTANT}>{turn.text}</div>
                }}
                {sending and <div className={BUBBLE_ASSISTANT + " text-muted"}>Thinking…</div>}
            </div>
            <div className="border-t border-line px-3 py-3">
                <div className="mb-2"><Notice tone="error" message={failure} /></div>
                <form
                    className="flex items-end gap-2"
                    onSubmit={lambda (e: FormEvent) { e.preventDefault(); askQuestion(draft); }}
                >
                    <textarea
                        aria-label="Ask a planning question"
                        rows={2}
                        maxLength={1000}
                        placeholder="e.g. Can I finish Project 2 before Friday?"
                        className={FIELD_INLINE + " min-h-[44px] flex-1 resize-none"}
                        value={draft}
                        onChange={lambda (e: ChangeEvent) { draft = e.target.value; }}
                        onKeyDown={onInputKeys}
                    ></textarea>
                    <button type="submit" className={BUTTON_PRIMARY + " min-h-[44px]"} disabled={sending or not draft.strip()}>Ask</button>
                </form>
            </div>
        </section>}
        <button
            type="button"
            aria-expanded={open}
            aria-label={"Close the planning assistant" if open else "Open the planning assistant"}
            className="fixed right-3 bottom-[80px] z-30 inline-flex min-h-[44px] items-center gap-2 rounded-full border border-ink bg-ink px-4 py-2.5 text-[13px] font-semibold text-white shadow-[0_6px_20px_rgba(18,21,26,0.25)] cursor-pointer desk:right-6 desk:bottom-6"
            onClick={lambda (e: MouseEvent) { open = not open; }}
        >
            <span aria-hidden="true">✦</span>
            {"Close" if open else "Ask"}
        </button>
    </>
}
