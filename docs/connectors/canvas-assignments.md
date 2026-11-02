# Canvas assignment import preview

Part of #17. This is an offline conversion layer, not a live Canvas connection.
The fixture contains invented data shaped like a page from the Canvas
[List assignments API](https://developerdocs.instructure.com/services/canvas/resources/assignments).
No Canvas token, sponsor approval, or model API key is needed for these commands.

Run from the repository root:

```bash
jac run connectors/canvas_assignments.jac -- fixtures/canvas/assignments.json
jac check connectors/canvas_assignments.jac connectors/canvas_assignments.test.jac
jac test connectors/canvas_assignments.jac
```

The fixture includes a coding assignment, an assignment without a due date,
and an assignment without a description. The command prints normalized JSON.

## Contract

| Canvas field | Draft field | Handling |
|---|---|---|
| `id` | `source_assignment_id` | Positive integer converted to a string |
| `course_id` | `source_course_id` | External Canvas ID, not a local graph ID |
| `name` | `title` | Required, trimmed, nonempty |
| `description` | `description` | HTML converted to plain text; null/missing becomes empty |
| `due_at` | `due_at` | Timezone required when provided; normalized to UTC; null/missing becomes empty |
| `html_url` | `source_url` | Optional HTTPS link without embedded credentials |
| Derived | `needs_description` | True when the cleaned description is empty |

`convert_assignment(raw)` converts one object. `convert_assignments(raw)`
converts an array and rejects duplicate `(source_course_id, source_assignment_id)`
pairs within that array. Invalid records fail the batch rather than being silently
skipped. Inputs are not modified.

HTML cleanup uses the standard library HTML parser, preserves paragraph/list/row
boundaries and inline words, decodes entities once, and excludes comments,
scripts, and styles. It does not download linked files or extract image/PDF text.
An assignment whose instructions exist only in an attachment needs user input.

## Proposed integration flow

1. After Canvas access is approved, fetch the user's selected course's assignments
   using read-only access. Follow API pagination before passing the combined
   records to the converter. Network/auth/pagination are not implemented here.
2. Resolve the Canvas course to a CourseCrusher course owned by the current user.
   Never pass `source_course_id` directly as the local `course_id`.
3. Let the user choose an assignment and review its title, cleaned description,
   and due date. If `needs_description` is true, request instructions before AI use.
4. Pass the reviewed `description` to the existing `break_down_assignment` endpoint.
   The integration test uses `break_down` with MockLLM to verify this text boundary.
5. Let the user review/edit subtasks and explicitly confirm before `add_assignment`.
   Keep ISO timezone information; convert to the user's zone when filling a local
   datetime input, rather than dropping the UTC suffix.

## Remaining work

- Sponsor, access request, institution-approved authentication, and live API checks.
- Course mapping, import controls in the UI, and per-user source metadata storage.
- Idempotent re-imports: before saving, check persisted source identity scoped to
  the Canvas instance and current user. This module only checks in-batch duplicates.
- Real-model quality checks remain tracked in #3; mock integration is not a
  substitute for evaluating model output.

This PR does not close #17 or add graph fields, endpoints, automatic scheduling,
or database writes. Source fields are retained in the draft for later integration.

## Web sample preview

On Breakdown, click **Load Canvas samples**, then choose an assignment.
The form shows cleaned instructions and a due date in the profile timezone.
Choose the local course and review/edit the fields before clicking **Break down assignment**.
Missing descriptions must be filled in. Changing samples clears the old breakdown and fit preview.
Nothing is stored until **Add to plan**. Samples can be loaded repeatedly and do not provide import deduplication.
This preview uses invented data and does not connect to Canvas.

For a demo without a model API key:

```bash
COURSE_CRUSHER_LLM_FIXTURE=e2e/breakdown_fixture.json jac run --port 8012
```

The model fixture returns canned subtasks, so this tests the UI flow, not model quality.
With Chrome/Chromium available (or JACBROWSER_CHROME set), run:

```bash
CANVAS_SAMPLES=1 BASE_URL=http://localhost:8012 bash e2e/run.sh
```

This checks missing instructions, HTML cleanup, local dates, breakdown, clearing stale output,
and the existing confirmation-to-Today/Courses flow using a fresh test account.
