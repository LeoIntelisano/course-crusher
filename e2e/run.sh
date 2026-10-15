#!/usr/bin/env bash
# End-to-end check of the main flow in a real (headless) browser.
#
# Start the app with the canned breakdown so no API key is needed:
#   COURSE_CRUSHER_LLM_FIXTURE=e2e/breakdown_fixture.json jac run
# Then, in another terminal:
#   e2e/run.sh                     # defaults to http://localhost:8000
#   BASE_URL=http://localhost:8010 e2e/run.sh
#
# Each run signs up a fresh throwaway account, so it never touches real data.
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8000}"
JAC="${JAC:-jac}"
SESSION="cc-e2e-$$"
STAMP="$(date +%s)"
EMAIL="e2e-${STAMP}@coursecrusher.test"
PASSWORD="${E2E_PASSWORD:-e2e-local-${STAMP}}"
TIMEOUT_SECONDS=20

browse() { "$JAC" browse -s "$SESSION" "$@"; }
cleanup() { browse close >/dev/null 2>&1 || true; }
trap cleanup EXIT

step() { printf '• %s\n' "$1"; }
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1" >&2; exit 1; }

# Poll the page text until it contains $1.
expect_text() {
  local needle="$1" waited=0
  until browse get text body 2>/dev/null | grep -qF -- "$needle"; do
    sleep 1
    waited=$((waited + 1))
    [ "$waited" -lt "$TIMEOUT_SECONDS" ] || fail "page never showed: $needle"
  done
  pass "shows \"$needle\""
}

# Poll until the page text no longer contains $1.
expect_no_text() {
  local needle="$1" waited=0
  while browse get text body 2>/dev/null | grep -qF -- "$needle"; do
    sleep 1
    waited=$((waited + 1))
    [ "$waited" -lt "$TIMEOUT_SECONDS" ] || fail "page still shows: $needle"
  done
  pass "no longer shows \"$needle\""
}

expect_url() {
  local suffix="$1" waited=0
  until browse get url 2>/dev/null | grep -qE -- "${suffix}\$"; do
    sleep 1
    waited=$((waited + 1))
    [ "$waited" -lt "$TIMEOUT_SECONDS" ] || fail "never reached $suffix (at $(browse get url))"
  done
  pass "at $suffix"
}

# Click the first button whose text contains $1 (React handles synthetic clicks).
click_button() {
  local label="$1"
  browse eval "(() => { const b = [...document.querySelectorAll('button')].find(x => x.textContent.includes('$label') && !x.disabled); if (!b) throw new Error('no button: $label'); b.click(); return true; })()" >/dev/null \
    || fail "couldn't click \"$label\""
}

# Set an input React controls (date/time inputs ignore synthetic typing).
set_value() {
  local selector="$1" value="$2"
  browse eval "(() => { const i = document.querySelector('$selector'); const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set; setter.call(i, '$value'); i.dispatchEvent(new Event('input', { bubbles: true })); return true; })()" >/dev/null \
    || fail "couldn't set $selector"
}

step "Protected pages redirect to sign-in"
browse open "$BASE_URL/" >/dev/null
expect_url "/login"

step "Sign up"
browse navigate "$BASE_URL/signup" >/dev/null
browse fill '#signup-name' 'E2E Student' >/dev/null
browse fill '#signup-email' "$EMAIL" >/dev/null
browse fill '#signup-password' "$PASSWORD" >/dev/null
click_button 'Create account'
expect_url "/"
expect_text "Nothing to plan yet"
[ "$(browse get title)" = "Today · CourseCrusher" ] && pass "page title" || fail "page title is $(browse get title)"

step "Add a course and a class time"
browse navigate "$BASE_URL/courses" >/dev/null
expect_text "Add a course"
browse fill '#course-code' 'eecs 445' >/dev/null
browse fill '#course-name' 'Machine Learning' >/dev/null
click_button 'Add course'
expect_text "EECS 445 · Machine Learning"
click_button 'Add class time'
browse fill '#meeting-location' 'Chrysler 220' >/dev/null
set_value '#meeting-start' '06:00'
set_value '#meeting-end' '07:00'
for day in Mon Tue Wed Thu Fri Sat Sun; do click_button "$day"; done
click_button 'Save class time'
expect_text "Mon Tue Wed Thu Fri Sat Sun 6:00 – 7:00 AM · Chrysler 220"

step "Break down an assignment"
browse navigate "$BASE_URL/breakdown" >/dev/null
expect_text "Break down a new assignment"
browse fill '#bd-title' 'Project 2' >/dev/null
set_value '#bd-due' '2030-01-15T23:59'
browse fill '#assignment-input' 'Project 2: implement logistic regression from scratch. Submit train.py and a short report with a learning-rate ablation.' >/dev/null
click_button 'Break down assignment'
expect_text "Agent breakdown — 5 subtasks, 3h 20m total"
expect_text "of buffer"
expect_text "Deep Work kept off late nights"

step "Review the subtasks and add them to the plan"
browse click 'button[aria-label="Include Proofread and submit to Canvas"]' >/dev/null
expect_text "Add 4 to plan"
click_button 'Add 4 to plan'
expect_text "Added 4 subtasks to your plan."

step "Today shows the agent's pick"
browse navigate "$BASE_URL/" >/dev/null
expect_text "Set up train.py skeleton and data loader"
expect_text "Why now:"
click_button 'Start 35-min focus'
expect_text "Focus block running"
click_button 'Mark done'
expect_no_text "Set up train.py skeleton and data loader"
expect_text "Implement the gradient descent loop"

step "The week plan lists the remaining steps and the class"
browse navigate "$BASE_URL/plan" >/dev/null
expect_text "Run the learning-rate ablation and save loss curves"
expect_text "EECS 445 Lecture"

step "Protected hours and sign out"
browse navigate "$BASE_URL/settings" >/dev/null
expect_text "Protected hours"
browse fill '#block-label' 'Dinner & gym' >/dev/null
click_button 'Add'
expect_text "Dinner & gym is now protected."
click_button 'Sign out'
expect_url "/login"
browse navigate "$BASE_URL/plan" >/dev/null
expect_url "/login"

printf '\nAll end-to-end checks passed.\n'
