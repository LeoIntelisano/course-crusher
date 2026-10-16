"""Today screen actions. Each one writes, then re-plans through the shared context."""

impl TodayPage.markDone(task_id: str) -> None {
    busy = True;
    result: CourseResult | None = None;
    try {
        result = await set_task_done(task_id, True);
    } except Exception as err {
        failure = error_message(err);
        busy = False;
        return;
    }
    failure = "" if result and result.ok else (result.error if result else "");
    focusing = False;
    swap_index = 0;
    await ctx.refreshToday();
    busy = False;
}

impl TodayPage.reschedule(task_id: str) -> None {
    busy = True;
    result: ActionResult | None = None;
    try {
        result = await reschedule_task(task_id);
    } except Exception as err {
        failure = error_message(err);
        busy = False;
        return;
    }
    failure = "" if result and result.ok else (result.error if result else "");
    swap_index = 0;
    await ctx.refreshToday();
    busy = False;
}

impl TodayPage.skipToday(task_id: str) -> None {
    busy = True;
    result: ActionResult | None = None;
    try {
        result = await skip_task_today(task_id);
    } except Exception as err {
        failure = error_message(err);
        busy = False;
        return;
    }
    failure = "" if result and result.ok else (result.error if result else "");
    swap_index = 0;
    await ctx.refreshToday();
    busy = False;
}
