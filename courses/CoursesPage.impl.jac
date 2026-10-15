"""Courses handlers. Every write returns the fresh course list, so no extra fetch is needed."""

impl CoursesPage.load -> None {
    latest: list[CourseView] = [];
    try {
        latest = await list_courses();
    } except Exception as err {
        failure = error_message(err);
        loaded = True;
        return;
    }
    courses = latest;
    loaded = True;
}

impl CoursesPage.apply(result: CourseResult | None) -> bool {
    if result is None {
        failure = "No response from the server.";
        return False;
    }
    courses = result.courses;
    failure = "" if result.ok else result.error;
    if result.ok {
        await ctx.refreshToday();
    }
    return result.ok;
}

impl CoursesPage.createCourse -> None {
    busy = True;
    result: CourseResult | None = None;
    try {
        result = await add_course(code, name);
    } except Exception as err {
        failure = error_message(err);
        busy = False;
        return;
    }
    if await apply(result) {
        code = "";
        name = "";
    }
    busy = False;
}

impl CoursesPage.createMeeting -> None {
    busy = True;
    result: CourseResult | None = None;
    try {
        result = await add_meeting(meeting_course, meeting_kind, meeting_days, meeting_start, meeting_end, meeting_location);
    } except Exception as err {
        failure = error_message(err);
        busy = False;
        return;
    }
    if await apply(result) {
        meeting_course = "";
        meeting_location = "";
    }
    busy = False;
}

impl CoursesPage.deleteCourse(course_id: str) -> None {
    matching = [c for c in courses if c.id == course_id];
    label = matching[0].code if matching else "this course";
    if not window.confirm(f"Remove {label} with its class times, assignments and subtasks?") {  # jac:ignore[W2001]
        return;
    }
    busy = True;
    result: CourseResult | None = None;
    try {
        result = await remove_course(course_id);
    } except Exception as err {
        failure = error_message(err);
        busy = False;
        return;
    }
    await apply(result);
    busy = False;
}

impl CoursesPage.deleteMeeting(meeting_id: str) -> None {
    busy = True;
    result: CourseResult | None = None;
    try {
        result = await remove_meeting(meeting_id);
    } except Exception as err {
        failure = error_message(err);
        busy = False;
        return;
    }
    await apply(result);
    busy = False;
}

impl CoursesPage.deleteAssignment(assignment_id: str) -> None {
    if not window.confirm("Remove this assignment and its subtasks from your plan?") {  # jac:ignore[W2001]
        return;
    }
    busy = True;
    result: CourseResult | None = None;
    try {
        result = await remove_assignment(assignment_id);
    } except Exception as err {
        failure = error_message(err);
        busy = False;
        return;
    }
    await apply(result);
    busy = False;
}

impl CoursesPage.toggleTask(task_id: str, done: bool) -> None {
    busy = True;
    result: CourseResult | None = None;
    try {
        result = await set_task_done(task_id, done);
    } except Exception as err {
        failure = error_message(err);
        busy = False;
        return;
    }
    await apply(result);
    busy = False;
}

impl CoursesPage.saveTags(course_id: str, tags: list[str]) -> None {
    busy = True;
    result: CourseResult | None = None;
    try {
        result = await set_course_tags(course_id, tags);
    } except Exception as err {
        failure = error_message(err);
        busy = False;
        return;
    }
    await apply(result);
    busy = False;
}

impl CoursesPage.saveColor(course_id: str, color: str) -> None {
    busy = True;
    result: CourseResult | None = None;
    try {
        result = await set_course_color(course_id, color);
    } except Exception as err {
        failure = error_message(err);
        busy = False;
        return;
    }
    await apply(result);
    busy = False;
}

impl CoursesPage.unlinkEvent(title: str) -> None {
    busy = True;
    result: CourseResult | None = None;
    try {
        result = await unlink_event(title);
    } except Exception as err {
        failure = error_message(err);
        busy = False;
        return;
    }
    await apply(result);
    busy = False;
}
