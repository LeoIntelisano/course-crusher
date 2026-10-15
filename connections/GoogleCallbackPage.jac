"""Where Google sends the browser after consent: finish the connection, then go back."""

import from "@jac/runtime" { Link, useLocation }
import from .google_link { ConnectResult, finish_google_connect }
import from ..shell.PlannerContext { usePlanner }
import from ..shared.errors { error_message }
import from ..shared.styles { CARD }
import from ..shared.ui { EmptyState, Notice }

# One exchange per page load: a code is single-use, and React may mount this twice.
glob pending_exchange: any = None;

def:pub GoogleCallbackPage -> JsxElement {
    ctx: any = usePlanner();
    location: any = useLocation();
    has outcome: str = "";
    has failure: str = "";

    async can with entry {
        # URLSearchParams is a browser constructor the checker has no stub for.
        params: any = new(URLSearchParams, location.search);  # jac:ignore[E1053]
        denied = str(params.get("error") or "");
        code = str(params.get("code") or "");
        state = str(params.get("state") or "");
        if denied {
            failure = "Google Calendar wasn't connected: access was declined.";
            return;
        }
        result: ConnectResult | None = None;
        try {
            if pending_exchange is None {
                pending_exchange = finish_google_connect(code, state);
            }
            result = await pending_exchange;
        } except Exception as err {
            failure = error_message(err);
            return;
        }
        if result and result.ok {
            outcome = "Google Calendar is connected. Your plan now works around your busy time.";
            await ctx.refreshToday();
        } else {
            failure = result.error if result else "Google sign-in didn't complete.";
        }
    }

    <section className={CARD + " mx-auto max-w-[560px]"}>
        {if not outcome and not failure {
            <EmptyState title="Connecting Google Calendar…" detail="This takes a moment." />
        }}
        <div className="flex flex-col gap-3 p-4">
            <Notice tone="success" message={outcome} />
            <Notice tone="error" message={failure} />
            {(outcome or failure) and <Link to="/connections" className="text-[13px] font-semibold text-brand">Back to Connections</Link>}
        </div>
    </section>
}
