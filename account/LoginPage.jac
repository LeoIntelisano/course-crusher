"""Sign in with email and password."""

import from "@jac/runtime" { Link, Navigate, jacIsLoggedIn, jacLogin, useNavigate }
import from .AuthCard { AuthCard }
import from ..shared.styles { BUTTON_PRIMARY, FIELD, LABEL }
import from ..shared.ui { Notice }

def:pub LoginPage -> JsxElement {
    has email: str = "";
    has password: str = "";
    has failure: str = "";
    has busy: bool = False;
    nav = useNavigate();

    async def submit(e: FormEvent) -> None {
        e.preventDefault();
        if not email.strip() or not password {
            failure = "Enter your email and password.";
            return;
        }
        busy = True;
        ok: bool = False;
        try {
            ok = await jacLogin(email.strip(), password);
        } except Exception {
            ok = False;
        }
        busy = False;
        if not ok {
            failure = "That email and password don't match an account.";
            return;
        }
        nav("/", {"replace": True});
    }

    can with entry {
        document.title = "Sign in · CourseCrusher";  # jac:ignore[W2001]
    }

    if jacIsLoggedIn() {
        return <Navigate to="/" replace={True} />;
    }

    <AuthCard title="Sign in" subtitle="Pick up where your plan left off.">
        <form onSubmit={submit} noValidate={True} className="flex flex-col gap-4">
            <div>
                <label className={LABEL} htmlFor="login-email">Email</label>
                <input
                    id="login-email"
                    type="email"
                    autoComplete="email"
                    className={FIELD}
                    value={email}
                    onChange={lambda (e: ChangeEvent) { email = e.target.value; }}
                />
            </div>
            <div>
                <label className={LABEL} htmlFor="login-password">Password</label>
                <input
                    id="login-password"
                    type="password"
                    autoComplete="current-password"
                    className={FIELD}
                    value={password}
                    onChange={lambda (e: ChangeEvent) { password = e.target.value; }}
                />
            </div>
            <Notice tone="error" message={failure} />
            <button type="submit" className={BUTTON_PRIMARY + " w-full min-h-[44px]"} disabled={busy}>
                {"Signing in…" if busy else "Sign in"}
            </button>
        </form>
        <p className="mt-4 mb-0 text-center text-[12.5px] text-muted">
            New here? <Link to="/signup" className="font-semibold text-brand">Create an account</Link>
        </p>
    </AuthCard>
}
