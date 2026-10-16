# CourseCrusher

Paste an assignment, get it broken into tiered subtasks by an AI agent, and let
the planner fit them into the free time between your classes. Built in
[Jac](https://www.jaseci.org/): one codebase for the server, the React UI and a CLI.

The UI follows `wireframes/index.html` (kept as the design reference).

| Screen | What works |
|---|---|
| **Today** | The agent's pick with a *why now* built from your calendar, energy and deadlines; a real focus timer; Reschedule, Swap task, Not today, Mark done; the rest of today's queue; this week's load by tier; the auto-fitted timeline; connection status |
| **Breakdown** | Paste an assignment → AI subtasks (tier + estimate) → toggle or edit them → live *Where it fits* and *Agent checks* → **Add N to plan**. Nothing is scheduled until you confirm |
| **Plan** | The next seven days, grouped by day, plus anything that doesn't fit |
| **Courses** | Courses, weekly class times (treated as fixed events), assignments and their subtasks |
| **Connections** | Google Calendar (free/busy only) with per-account OAuth |
| **Settings** | Day start/end, Deep Work cutoff, buffer around classes, shortest slot, protected hours, sign out |

Every endpoint requires sign-in, and each student's data lives on their own graph root.

## Setup

The project pins `jac` 0.37.23, the native binary from
[jaseci-labs/jac releases](https://github.com/jaseci-labs/jac/releases) (not the
`jaclang` PyPI package). On macOS arm64:

```bash
gh release download v0.37.23 --repo jaseci-labs/jac --pattern 'jac-0.37.23-macos-aarch64*'
shasum -a 256 -c jac-0.37.23-macos-aarch64.sha256
chmod +x jac-0.37.23-macos-aarch64 && mv jac-0.37.23-macos-aarch64 ~/.local/bin/jac
```

If `jac install` crashes while creating `.jac/venv`, build the venv with uv first
(`--seed` matters: `jac install` upgrades packages with pip):

```bash
uv venv .jac/venv --python python3.14 --seed
```

Then install Python and npm dependencies, and add your keys:

```bash
jac install
cp .env.example .env
```

## Run

```bash
jac run
```

Serves the app with hot reload at <http://localhost:8000>. Server-side `.jac`
changes need a restart; client components reload in place.

Without an API key, run with canned breakdown output:

```bash
COURSE_CRUSHER_LLM_FIXTURE=e2e/breakdown_fixture.json jac run
```

The CLI is a second app in the same workspace:

```bash
jac run cli -- free-slots --fixture fixtures/calendar/freebusy_sample_day.json --date 2026-10-06 --tz America/Detroit
```

## Test

```bash
jac test suite.jac
```

Runs every server-side suite once: the scheduling engine, endpoints (through an
in-process server with real sign-in and per-test storage), the Google connectors,
the breakdown walker (MockLLM, no API key) and the pure UI helpers.

```bash
jac test cli
```

Runs the CLI's tests.

```bash
e2e/run.sh
```

Drives the whole flow in a headless browser against a running server: sign up,
add a course and class time, break down an assignment, add it to the plan, focus,
mark done, protected hours, sign out, and the auth redirect. Start the server with
the fixture variable above; set `BASE_URL` if it isn't on port 8000.

`web.jac` can't be the test target: it renders the browser app, so the runner treats
it as client code. That's why `suite.jac` exists.

## Configuration

All settings come from environment variables (see `.env.example`):

| Variable | Used for |
|---|---|
| `OPENAI_API_KEY` | The AI breakdown with the default `gpt-4o-mini` model |
| `LLM_MODEL` + `ANTHROPIC_API_KEY` | Switch the breakdown to another LiteLLM model, e.g. Claude |
| `GOOGLE_WEB_CLIENT_SECRETS_FILE` | OAuth client ("Web application") for Calendar in the app |
| `GOOGLE_OAUTH_REDIRECT_URI` | Must match the client's authorized redirect URI |
| `GOOGLE_CLIENT_SECRETS_FILE` | OAuth client ("Desktop app") for the CLI's `--google` |
| `JAC_SERVE_AUTH_SECRET` | JWT signing secret in production |
| `JAC_ADMIN_PASSWORD` | Initial password for Jac's built-in `/admin` portal; set it before any shared deploy |
| `COURSE_CRUSHER_LLM_FIXTURE` | Canned breakdowns for demos and e2e runs only |

Calendar setup and the privacy trade-offs are in `docs/connectors/google-calendar.md`.

## How it's organized

Folders hold a feature's server and client code side by side.

| Path | What's in it |
|---|---|
| `web.jac` | Web app entry: endpoint imports, then the client `app` |
| `main.jac` | CLI entry (`free-slots`) |
| `breakdown.jac` | AI breakdown: `Subtask` contract, prompt, walker, `break_down_assignment` endpoint |
| `scheduling/` | `time_slots.jac` (free gaps between busy blocks) and `planner.jac` (the pure scheduling engine) |
| `planner/` | Loads a student's data (`inputs`), builds the Today/Plan/fit views (`views`, `fit`), endpoints (`service`), and the Today and Plan screens |
| `courses/` | Course, ClassMeeting, Assignment and Task nodes and endpoints; the Courses and Breakdown screens |
| `account/` | Profile and protected hours; sign-in, sign-up and Settings screens |
| `connections/` | Per-student Google link and its endpoints; Connections and OAuth callback screens |
| `connectors/` | Google Calendar freeBusy client (CLI flow) and the web OAuth flow |
| `shell/` | Routes, layout, sidebar, top bar, tab bar, and the shared planner context |
| `shared/` | Formatting, time parsing, error messages, Tailwind class strings, small UI pieces |
| `styles/app.css` | Tailwind v4 with the wireframe's design tokens |
| `e2e/` | Browser end-to-end script and its canned breakdown |

### Planning rules

`scheduling/planner.jac` re-plans on every request; nothing is stored as a schedule.

1. Free time is each day's window minus class times (padded by the buffer), Google
   busy time and protected hours. Gaps shorter than the shortest useful slot are dropped.
2. Earliest deadline first. An assignment's subtasks keep their order.
3. Each subtask goes into the earliest gap it fits whole; subtasks are never split.
4. Deep Work must end by the Deep Work cutoff.
5. With energy set to Low, today's Deep Work moves to a later day unless it's due today.
6. Reschedule moves a subtask past its current slot; Not today moves it to tomorrow.
