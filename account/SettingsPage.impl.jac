"""Settings handlers: load the profile, save it, and edit protected hours."""

impl SettingsPage.fill(view: ProfileView) {
    profile = view;
    display_name = view.display_name;
    timezone = view.timezone;
    day_start = view.day_start;
    day_end = view.day_end;
    cutoff = view.deep_work_cutoff;
    buffer = str(view.buffer_minutes);
    min_slot = str(view.min_slot_minutes);
}

impl SettingsPage.load -> None {
    latest: ProfileView | None = None;
    try {
        latest = await get_profile();
    } except Exception as err {
        failure = error_message(err);
        return;
    }
    if latest {
        fill(latest);
    }
}

impl SettingsPage.applyResult(result: ProfileResult | None, success: str) -> None {
    if result and result.ok and result.profile {
        fill(result.profile);
        notice = success;
        failure = "";
        await ctx.refreshToday();
        return;
    }
    notice = "";
    failure = result.error if result else "Couldn't save your settings.";
}

impl SettingsPage.saveProfile -> None {
    busy = True;
    result: ProfileResult | None = None;
    try {
        result = await save_profile(
            display_name, timezone, day_start, day_end, cutoff, int(buffer or "0"), int(min_slot or "0")
        );
    } except Exception as err {
        failure = error_message(err);
        busy = False;
        return;
    }
    await applyResult(result, "Settings saved. Your plan has been re-fitted.");
    busy = False;
}

impl SettingsPage.addBlock -> None {
    busy = True;
    result: ProfileResult | None = None;
    try {
        result = await add_protected_hours(block_label, block_start, block_end);
    } except Exception as err {
        failure = error_message(err);
        busy = False;
        return;
    }
    await applyResult(result, f"{block_label.strip()} is now protected.");
    if result and result.ok {
        block_label = "";
    }
    busy = False;
}

impl SettingsPage.removeBlock(block_id: str) -> None {
    busy = True;
    result: ProfileResult | None = None;
    try {
        result = await remove_protected_hours(block_id);
    } except Exception as err {
        failure = error_message(err);
        busy = False;
        return;
    }
    await applyResult(result, "Protected time removed.");
    busy = False;
}
