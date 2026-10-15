"""Every module with tests, so one command runs the whole server-side suite once.

    jac test suite.jac     # endpoints, planner, connectors, and the pure UI helpers
    jac test cli           # the command-line app

`web.jac` can't be the test target: it renders the browser app, so the runner
treats it as client code. `suite.test.jac` holds the cross-cutting endpoint tests.
"""

import from account.store { get_profile }
import from breakdown { break_down_assignment }
import from connections.google_link { calendar_status }
import from courses.drafts { DraftRow }
import from courses.store { list_courses }
import from planner.grid { item_box }
import from planner.service { get_today }
import from shared.errors { error_message }
import from shared.format { format_minutes }
import from shell.nav { title_for }
import from shell.status { free_text }
