"""Breakdown handlers: courses, the AI call, the live fit preview, and saving."""

impl BreakdownPage.loadCourses -> None {
    latest: list[CourseView] = [];
    try {
        latest = await list_courses();
    } except Exception as err {
        failure = error_message(err);
        return;
    }
    courses = latest;
    if latest and not course_id {
        course_id = latest[0].id;
    }
}

impl BreakdownPage.createCourse -> None {
    result: CourseResult | None = None;
    try {
        result = await add_course(new_code, "");
    } except Exception as err {
        failure = error_message(err);
        return;
    }
    if result and result.ok {
        courses = result.courses;
        matches = [c for c in result.courses if c.code == new_code.strip().upper()];
        course_id = matches[0].id if matches else (result.courses[0].id if result.courses else "");
        new_code = "";
        failure = "";
        await ctx.refreshToday();
    } else {
        failure = result.error if result else "";
    }
}

impl BreakdownPage.breakDown -> None {
    if breaking {
        return;
    }
    if not course_id {
        failure = "Add the course first.";
        return;
    }
    if not description.strip() {
        failure = "Paste the assignment description first.";
        return;
    }
    breaking = True;
    notice = "";
    result: BreakdownResult | None = None;
    try {
        result = await break_down_assignment(description);
    } except Exception as err {
        failure = error_message(err);
        breaking = False;
        return;
    }
    breaking = False;
    if not result or not result.ok {
        failure = result.error if result else "The breakdown didn't come back.";
        return;
    }
    failure = "";
    editing = False;
    source = description.strip();
    next_rows = [
        DraftRow(title=step.title, tier=str(step.tier), minutes=step.estimated_duration)
        for step in result.subtasks
    ];
    rows = next_rows;
    await refreshFit(next_rows);
}

impl BreakdownPage.refreshFit(next_rows: list[DraftRow]) -> None {
    # Toggles fire refreshes without waiting; only the newest answer may land.
    fit_request = fit_request + 1;
    request = fit_request;
    chosen_rows = included_rows(next_rows);
    if not chosen_rows {
        preview = None;
        return;
    }
    drafts = [
        SubtaskDraft(title=row.title, tier=row.tier, estimated_duration=row.minutes)
        for row in chosen_rows
    ];
    result: FitResult | None = None;
    try {
        result = await preview_fit(default_title(title, source), due_at, drafts);
    } except Exception as err {
        if request == fit_request {
            preview = None;
            failure = error_message(err);
        }
        return;
    }
    if request != fit_request {
        return;
    }
    if result and result.ok {
        preview = result.preview;
    } else {
        preview = None;
        failure = result.error if result else "";
    }
}

impl BreakdownPage.addToPlan -> None {
    chosen_rows = included_rows(rows);
    if not chosen_rows {
        failure = "Select at least one subtask to add.";
        return;
    }
    saving = True;
    drafts = [
        SubtaskDraft(title=row.title, tier=row.tier, estimated_duration=row.minutes)
        for row in chosen_rows
    ];
    result: CourseResult | None = None;
    try {
        result = await add_assignment(course_id, default_title(title, source), source, due_at, drafts);
    } except Exception as err {
        failure = error_message(err);
        saving = False;
        return;
    }
    saving = False;
    if not result or not result.ok {
        failure = result.error if result else "Couldn't add the subtasks.";
        return;
    }
    noun = "subtask" if len(chosen_rows) == 1 else "subtasks";
    notice = f"Added {len(chosen_rows)} {noun} to your plan.";
    failure = "";
    rows = [];
    preview = None;
    editing = False;
    title = "";
    due_at = "";
    description = "";
    source = "";
    courses = result.courses;
    await ctx.refreshToday();
}
