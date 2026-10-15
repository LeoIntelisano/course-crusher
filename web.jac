"""CourseCrusher web app entry: server endpoints, then the browser UI.

    jac run            # serve at http://localhost:8000 (dev mode, hot reload)
    jac test suite.jac # every server-side test (see suite.jac)

Every endpoint is `:protect`, so each student only ever sees their own root.
"""

import from account.store {
    ProfileResult,
    ProfileView,
    add_protected_hours,
    get_profile,
    remove_protected_hours,
    save_profile,
    set_energy,
    setup_account
}
import from breakdown { BreakdownResult, Subtask, break_down_assignment }
import from connections.google_link {
    CalendarStatus,
    ConnectResult,
    ConnectStart,
    calendar_status,
    disconnect_google,
    finish_google_connect,
    set_google_calendars,
    start_google_connect
}
import from courses.store {
    CourseResult,
    CourseView,
    SubtaskDraft,
    add_assignment,
    add_course,
    add_meeting,
    link_event,
    list_courses,
    remove_assignment,
    remove_course,
    remove_meeting,
    set_course_color,
    set_course_tags,
    set_task_done,
    unlink_event
}
import from planner.service {
    ActionResult,
    FitResult,
    get_calendar,
    get_today,
    get_week,
    preview_fit,
    reschedule_task,
    skip_task_today
}

import "./styles/app.css";
import from shell.AppRoutes { AppRoutes }

def:pub app -> JsxElement {
    <AppRoutes />
}
