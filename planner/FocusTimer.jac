"""A countdown for the current block. Finishing or marking done completes the subtask."""

import from "react" { useEffect }
import from ..shared.format { countdown_text }
import from ..shared.styles { BUTTON, BUTTON_PRIMARY }

glob TICK_MS: int = 1000;
glob SECONDS_PER_MINUTE: int = 60;

def:pub FocusTimer(minutes: int, onDone: Callable[[], None], onStop: Callable[[], None]) -> JsxElement {
    has remaining: int = minutes * SECONDS_PER_MINUTE;

    # setInterval needs its handle in the cleanup, which a `can with exit` closure can't see.
    useEffect(lambda {
        timer = setInterval(lambda { remaining = max(0, remaining - 1); }, TICK_MS);
        return lambda { clearInterval(timer); };
    }, []);

    finished = remaining == 0;
    <div className="mt-[15px] rounded-md border border-line bg-canvas px-[13px] py-[11px]" role="timer" aria-live="off">
        <div className="flex flex-wrap items-center gap-3">
            <span className="font-mono text-[28px] font-semibold tabular-nums tracking-[-0.5px]">{countdown_text(remaining)}</span>
            <span className="text-[12.5px] text-muted">{"Time's up — nice work." if finished else "Focus block running"}</span>
        </div>
        <div className="mt-3 flex flex-wrap gap-2">
            <button type="button" className={BUTTON_PRIMARY} onClick={lambda { onDone(); }}>Mark done</button>
            <button type="button" className={BUTTON} onClick={lambda { onStop(); }}>Stop</button>
        </div>
    </div>
}
