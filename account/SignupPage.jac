"""Create an account, sign in, and store the student's name and time zone."""

import from "@jac/runtime" { Link, Navigate, SignupResult, jacIsLoggedIn, jacLogin, jacSignup, useNavigate }
import from .AuthCard { AuthCard }
import from .store { ProfileResult, setup_account }
import from ..shared.styles { BUTTON_PRIMARY, FIELD, HINT, LABEL }
import from ..shared.ui { Notice }

glob MIN_PASSWORD_LENGTH: int = 8;
glob MAX_NAME_LENGTH: int = 80;
glob FALLBACK_TIMEZONE: str = "America/Detroit";

"""The browser's IANA zone, so the plan starts in local time."""
def browser_timezone -> str {
    # Intl is a browser global the checker has no stub for.
    resolved: any = Intl.DateTimeFormat().resolvedOptions();  # jac:ignore[E1032,W2001]
    return str(resolved.timeZone or FALLBACK_TIMEZONE);
}

def:pub SignupPage -> JsxElement {
    has name: str = "";
    has email: str = "";
    has password: str = "";
    has failure: str = "";
    has busy: bool = False;
    nav = useNavigate();

    def problem -> str {
        if not name.strip() {
            return "Tell us what to call you.";
        }
        if len(name.strip()) > MAX_NAME_LENGTH {
            return f"Keep your name under {MAX_NAME_LENGTH} characters.";
        }
        if "@" not in email {
            return "Enter a valid email address.";
        }
        if len(password) < MIN_PASSWORD_LENGTH {
            return f"Use at least {MIN_PASSWORD_LENGTH} characters for your password.";
        }
        return "";
    }

    async def submit(e: FormEvent) -> None {
        e.preventDefault();
        failure = problem();
        if failure {
            return;
        }
        busy = True;
        created: SignupResult | None = None;
        signed_in: bool = False;
        profile: ProfileResult | None = None;
        try {
            created = await jacSignup(email.strip(), password);
            if not created.success {
                failure = "An account with that email may already exist. Try signing in.";
                busy = False;
                return;
            }
            signed_in = await jacLogin(email.strip(), password);
            if not signed_in {
                failure = "Your account was created, but signing in failed. Try signing in.";
                busy = False;
                return;
            }
            profile = await setup_account(name, browser_timezone());
        } except Exception {
            failure = "Couldn't reach CourseCrusher. Check your connection and try again.";
            busy = False;
            return;
        }
        busy = False;
        # The account exists either way; send them to Settings to fix the name or zone.
        nav("/" if profile and profile.ok else "/settings", {"replace": True});
    }

    can with entry {
        document.title = "Create account · CourseCrusher";  # jac:ignore[W2001]
    }

    if jacIsLoggedIn() and not busy {
        return <Navigate to="/" replace={True} />;
    }

    <AuthCard title="Create your account" subtitle="Break assignments down and let the agent fit them into your week.">
        <form onSubmit={submit} noValidate={True} className="flex flex-col gap-4">
            <div>
                <label className={LABEL} htmlFor="signup-name">Name</label>
                <input
                    id="signup-name"
                    autoComplete="name"
                    className={FIELD}
                    value={name}
                    onChange={lambda (e: ChangeEvent) { name = e.target.value; }}
                />
            </div>
            <div>
                <label className={LABEL} htmlFor="signup-email">Email</label>
                <input
                    id="signup-email"
                    type="email"
                    autoComplete="email"
                    className={FIELD}
                    value={email}
                    onChange={lambda (e: ChangeEvent) { email = e.target.value; }}
                />
            </div>
            <div>
                <label className={LABEL} htmlFor="signup-password">Password</label>
                <input
                    id="signup-password"
                    type="password"
                    autoComplete="new-password"
                    aria-describedby="signup-password-hint"
                    className={FIELD}
                    value={password}
                    onChange={lambda (e: ChangeEvent) { password = e.target.value; }}
                />
                <p id="signup-password-hint" className={HINT}>{f"At least {MIN_PASSWORD_LENGTH} characters."}</p>
            </div>
            <Notice tone="error" message={failure} />
            <button type="submit" className={BUTTON_PRIMARY + " w-full min-h-[44px]"} disabled={busy}>
                {"Creating account…" if busy else "Create account"}
            </button>
        </form>
        <p className="mt-4 mb-0 text-center text-[12.5px] text-muted">
            Already have an account? <Link to="/login" className="font-semibold text-brand">Sign in</Link>
        </p>
    </AuthCard>
}
