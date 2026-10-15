"""Every module with tests, so one command runs the whole server-side suite once.

    jac test suite.jac     # endpoints, planner and connectors
    jac test cli           # the command-line app

Keeping the test target separate from `web.jac` lets the entry grow a client
section later. `suite.test.jac` holds the cross-cutting endpoint tests.
"""

import from account.store { get_profile }
import from breakdown { break_down_assignment }
import from connections.google_link { calendar_status }
import from courses.store { list_courses }
import from planner.service { get_today }
import from shared.format { format_minutes }
