"""Connections: Google Calendar (busy time only) and the state of Canvas."""

import from "@jac/runtime" { Link }
import from .google_link {
    CalendarStatus,
    ConnectResult,
    ConnectStart,
    calendar_status,
    disconnect_google,
    set_google_calendars,
    start_google_connect
}
import from ..shell.PlannerContext { usePlanner }
import from ..shared.errors { error_message }
import from ..shared.styles { BUTTON, BUTTON_DANGER, BUTTON_PRIMARY, CARD, CARD_STACK, COLUMNS, FIELD, HINT, LABEL }
import from ..shared.ui { CardHeader, Notice }

glob STATE_TEXT: dict[str, str] = {
    "connected": "Connected",
    "error": "Needs attention",
    "disconnected": "Not connected",
    "not_configured": "Not set up on this server"
};

def:pub ConnectionsPage -> JsxElement {
    ctx: any = usePlanner();
    has status: CalendarStatus | None = None;
    has calendars_text: str = "";
    has failure: str = "";
    has notice: str = "";
    has busy: bool = False;

    async def load -> None {
        latest: CalendarStatus | None = None;
        try {
            latest = await calendar_status();
        } except Exception as err {
            failure = error_message(err);
            return;
        }
        status = latest;
        calendars_text = ", ".join(latest.calendars) if latest else "";
    }

    async def connect -> None {
        busy = True;
        started: ConnectStart | None = None;
        try {
            started = await start_google_connect();
        } except Exception as err {
            failure = error_message(err);
            busy = False;
            return;
        }
        if started and started.ok {
            window.location.assign(started.url);  # jac:ignore[W2001]
            return;
        }
        failure = started.error if started else "Couldn't start Google sign-in.";
        busy = False;
    }

    async def saveCalendars -> None {
        busy = True;
        result: ConnectResult | None = None;
        ids = [part.strip() for part in calendars_text.split(",") if part.strip()];
        try {
            result = await set_google_calendars(ids);
        } except Exception as err {
            failure = error_message(err);
            busy = False;
            return;
        }
        if result and result.ok {
            status = result.status;
            notice = "Calendars saved. Your plan will use them from now on.";
            failure = "";
            await ctx.refreshToday();
        } else {
            failure = result.error if result else "";
        }
        busy = False;
    }

    async def disconnect -> None {
        busy = True;
        latest: CalendarStatus | None = None;
        try {
            latest = await disconnect_google();
        } except Exception as err {
            failure = error_message(err);
            busy = False;
            return;
        }
        status = latest;
        notice = "Google Calendar disconnected.";
        await ctx.refreshToday();
        busy = False;
    }

    async can with entry {
        await load();
    }

    state = status.state if status else "";
    linked = state == "connected" or state == "error";

    <div className={COLUMNS}>
        <div className={CARD_STACK}>
            <Notice tone="error" message={failure} />
            <Notice tone="success" message={notice} />
            <section className={CARD} aria-labelledby="google-h">
                <CardHeader title="Google Calendar" titleId="google-h" aside={STATE_TEXT.get(state, "Checking…")} />
                <div className="flex flex-col gap-3 px-4 pt-3 pb-4 text-[12.5px] text-body">
                    <p className="m-0">
                        CourseCrusher reads your events' names and times (read-only) to plan around them, show them on the Today calendar, and label them with the matching course. Nothing is copied or stored; your calendar is read when you open the app.
                    </p>
                    {if state == "error" and status {
                        <Notice tone="error" message={status.detail} />
                    }}
                    {if state == "connected" and status and not status.names {
                        <div className="flex flex-col gap-2">
                            <Notice tone="info" message="Connected for busy times only. Reconnect once to show event names and match them to your courses." />
                            <div><button type="button" className={BUTTON_PRIMARY} disabled={busy} onClick={lambda (e: MouseEvent) { connect(); }}>Reconnect for event names</button></div>
                        </div>
                    }}
                    {if state == "not_configured" {
                        <p className="m-0 text-muted">
                            The server needs a Google OAuth client. Set <code>GOOGLE_WEB_CLIENT_SECRETS_FILE</code> and <code>GOOGLE_OAUTH_REDIRECT_URI</code>, then restart. See docs/connectors/google-calendar.md.
                        </p>
                    }}
                    {if state == "disconnected" {
                        <div><button type="button" className={BUTTON_PRIMARY} disabled={busy} onClick={lambda (e: MouseEvent) { connect(); }}>Connect Google Calendar</button></div>
                    }}
                    {if linked {
                        <form
                            className="flex flex-col gap-2"
                            onSubmit={lambda (e: FormEvent) { e.preventDefault(); saveCalendars(); }}
                        >
                            <label className={LABEL} htmlFor="calendar-ids">Calendars to read</label>
                            <input
                                id="calendar-ids"
                                className={FIELD}
                                value={calendars_text}
                                onChange={lambda (e: ChangeEvent) { calendars_text = e.target.value; }}
                                aria-describedby="calendar-ids-hint"
                            />
                            <p id="calendar-ids-hint" className={HINT}>Comma-separated calendar IDs. "primary" is your main calendar; class calendars look like name@group.calendar.google.com.</p>
                            <div className="flex flex-wrap gap-2">
                                <button type="submit" className={BUTTON} disabled={busy}>Save calendars</button>
                                <button type="button" className={BUTTON_DANGER} disabled={busy} onClick={lambda (e: MouseEvent) { disconnect(); }}>Disconnect</button>
                            </div>
                        </form>
                    }}
                </div>
            </section>
            <section className={CARD} aria-labelledby="canvas-h">
                <CardHeader title="Canvas" titleId="canvas-h" aside="Not available yet" />
                <p className="m-0 px-4 pt-3 pb-4 text-[12.5px] text-body">
                    CourseCrusher doesn't read Canvas yet. Paste the assignment text on the <Link to="/breakdown" className="font-semibold text-brand">Breakdown</Link> screen instead.
                </p>
            </section>
        </div>
        <div className={CARD_STACK}>
            <section className={CARD} aria-labelledby="schedule-h">
                <CardHeader title="Class schedule" titleId="schedule-h" />
                <p className="m-0 px-4 pt-3 pb-4 text-[12.5px] text-body">
                    Lectures and labs you add under <Link to="/courses" className="font-semibold text-brand">Courses</Link> are treated as fixed events, with or without Google Calendar. Each course also lists the calendar names its Google events go by.
                </p>
            </section>
        </div>
    </div>
}
