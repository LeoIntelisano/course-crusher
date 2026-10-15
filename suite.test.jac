import from shared.api_testing { anonymous_client, call, post, signed_in_client }

"""Each endpoint with a well-formed body, so a 401 proves the auth check and not input validation."""
glob PROTECTED_CALLS: dict[str, dict[str, any]] = {
    "get_profile": {},
    "setup_account": {"display_name": "A", "timezone": "UTC"},
    "save_profile": {
        "display_name": "A", "timezone": "UTC", "day_start": "08:00", "day_end": "22:00",
        "deep_work_cutoff": "21:00", "buffer_minutes": 10, "min_slot_minutes": 15
    },
    "set_energy": {"energy": "High"},
    "add_protected_hours": {"label": "Dinner", "start": "17:00", "end": "18:00"},
    "remove_protected_hours": {"block_id": "x"},
    "break_down_assignment": {"assignment_text": "Write the report"},
    "calendar_status": {},
    "start_google_connect": {},
    "finish_google_connect": {"code": "c", "state": "s"},
    "disconnect_google": {},
    "set_google_calendars": {"calendar_ids": ["primary"]},
    "list_courses": {},
    "add_course": {"code": "EECS 445", "name": ""},
    "remove_course": {"course_id": "x"},
    "add_meeting": {"course_id": "x", "kind": "Lecture", "weekdays": [0], "start": "09:00", "end": "10:00", "location": ""},
    "remove_meeting": {"meeting_id": "x"},
    "add_assignment": {"course_id": "x", "title": "T", "description": "", "due_at": "", "subtasks": []},
    "remove_assignment": {"assignment_id": "x"},
    "set_task_done": {"task_id": "x", "done": True},
    "get_today": {},
    "get_week": {},
    "preview_fit": {"title": "T", "due_at": "", "subtasks": []},
    "reschedule_task": {"task_id": "x"},
    "skip_task_today": {"task_id": "x"}
};

test "every endpoint requires a signed-in student" {
    client = anonymous_client();
    try {
        for (endpoint, payload) in PROTECTED_CALLS.items() {
            response = post(client, endpoint, payload);
            assert response.status_code == 401, f"{endpoint} answered {response.status_code} without a token";
        }
    } finally {
        client.close();
    }
}

test "a new student gets a default profile and an empty plan" {
    client = signed_in_client();
    try {
        profile = call(client, "get_profile");
        today = call(client, "get_today");

        assert profile["timezone"] == "America/Detroit" and profile["energy"] == "High";
        assert today["up_next"] is None and today["queue"] == [];
        assert today["open_tasks"] == 0 and today["course_count"] == 0;
    } finally {
        client.close();
    }
}
