import from datetime { datetime, timedelta, timezone }
import from jaclang.testing.testing { JacTestClient }
import from shared.api_testing { call, signed_in_client }

def subtask_draft(title: str, tier: str, minutes: int) -> dict[str, any] {
    return {"title": title, "tier": tier, "estimated_duration": minutes};
}

"""A student in UTC with one course and a three-step assignment due in five days."""
def seeded_client -> JacTestClient {
    client = signed_in_client();
    call(client, "setup_account", {"display_name": "Test Student", "timezone": "UTC"});
    course = call(client, "add_course", {"code": "EECS 445", "name": "Machine Learning"})["courses"][0];
    due = (datetime.now(timezone.utc) + timedelta(days=5)).strftime("%Y-%m-%dT23:59");
    saved = call(client, "add_assignment", {
        "course_id": course["id"],
        "title": "Project 2",
        "description": "",
        "due_at": due,
        "subtasks": [
            subtask_draft("Set up train.py", "Shallow Work", 30),
            subtask_draft("Implement gradient descent", "Shallow Work", 45),
            subtask_draft("Submit", "Low Energy", 10)
        ]
    });
    assert saved["ok"], saved["error"];
    return client;
}

def task_ids(client: JacTestClient) -> list[str] {
    return [t["id"] for t in call(client, "list_courses")[0]["assignments"][0]["tasks"]];
}

def week_items(client: JacTestClient) -> list[dict[str, any]] {
    return [item for day in call(client, "get_week")["days"] for item in day["items"]];
}

test "today plans the saved subtasks" {
    client = seeded_client();
    try {
        ids = task_ids(client);
        today = call(client, "get_today");

        assert today["open_tasks"] == 3 and today["course_count"] == 1;
        assert today["display_name"] == "Test Student" and today["initials"] == "TS";
        assert today["up_next"] is not None and today["up_next"]["item"]["task_id"] == ids[0];
        assert today["up_next"]["why"];
        assert today["calendar"]["state"] == "not_configured";
    } finally {
        client.close();
    }
}

test "the week keeps the assignment's order and places every step" {
    client = seeded_client();
    try {
        ids = task_ids(client);
        week = call(client, "get_week");
        items = [item for day in week["days"] for item in day["items"]];

        assert len(week["days"]) == 7;
        assert [i["task_id"] for i in items] == ids;
        assert [i["start"] for i in items] == sorted([i["start"] for i in items]);
        assert week["unplaced"] == [] and week["at_risk"] == 0;
    } finally {
        client.close();
    }
}

test "done subtasks leave the plan" {
    client = seeded_client();
    try {
        ids = task_ids(client);
        call(client, "set_task_done", {"task_id": ids[0], "done": True});

        assert [i["task_id"] for i in week_items(client)] == ids[1:];
        assert call(client, "get_today")["open_tasks"] == 2;
    } finally {
        client.close();
    }
}

test "not today moves a subtask and its later steps off today" {
    client = seeded_client();
    try {
        ids = task_ids(client);
        result = call(client, "skip_task_today", {"task_id": ids[0]});

        assert result["ok"];
        first_day = call(client, "get_week")["days"][0];
        assert ids[0] not in [i["task_id"] for i in first_day["items"]];
        assert not call(client, "skip_task_today", {"task_id": "missing"})["ok"];
    } finally {
        client.close();
    }
}

test "reschedule moves a subtask past its current slot" {
    client = seeded_client();
    try {
        ids = task_ids(client);
        before = [i for i in week_items(client) if i["task_id"] == ids[2]][0];

        result = call(client, "reschedule_task", {"task_id": ids[2]});
        after = [i for i in week_items(client) if i["task_id"] == ids[2]][0];

        assert result["ok"];
        assert datetime.fromisoformat(after["start"]) >= datetime.fromisoformat(before["end"]);
        assert not call(client, "reschedule_task", {"task_id": "missing"})["ok"];
    } finally {
        client.close();
    }
}

test "preview_fit places proposed subtasks without saving them" {
    client = seeded_client();
    try {
        due = (datetime.now(timezone.utc) + timedelta(days=6)).strftime("%Y-%m-%dT23:59");
        result = call(client, "preview_fit", {
            "title": "Lab report",
            "due_at": due,
            "subtasks": [subtask_draft("Outline", "Shallow Work", 30), subtask_draft("Draft", "Low Energy", 20)]
        });

        assert result["ok"], result["error"];
        preview = result["preview"];
        assert [(b["position"], b["placed"]) for b in preview["blocks"]] == [(1, True), (2, True)];
        assert preview["days"] and preview["buffer_label"].endswith("of buffer");
        assert "No clash with 0 fixed events" in [c["message"] for c in preview["checks"]];
        assert call(client, "get_today")["open_tasks"] == 3;
    } finally {
        client.close();
    }
}

test "preview_fit validates its input" {
    client = seeded_client();
    try {
        bad_tier = call(client, "preview_fit", {"title": "X", "due_at": "", "subtasks": [subtask_draft("A", "Medium", 30)]});
        bad_due = call(client, "preview_fit", {"title": "X", "due_at": "soon", "subtasks": [subtask_draft("A", "Low Energy", 30)]});
        empty = call(client, "preview_fit", {"title": "X", "due_at": "", "subtasks": []});

        assert not bad_tier["ok"] and "unknown tier" in bad_tier["error"];
        assert not bad_due["ok"] and "Due date" in bad_due["error"];
        assert not empty["ok"];
    } finally {
        client.close();
    }
}

test "class meetings show up in the week as fixed events" {
    client = seeded_client();
    try {
        course_id = call(client, "list_courses")[0]["id"];
        call(client, "add_meeting", {
            "course_id": course_id, "kind": "Lecture", "weekdays": [0, 1, 2, 3, 4, 5, 6],
            "start": "11:00", "end": "12:20", "location": "Chrysler 220"
        });

        days = call(client, "get_week")["days"];

        assert all([("EECS 445 Lecture" in [e["title"] for e in d["events"]]) for d in days]);
        assert days[0]["events"][0]["detail"] == "11:00 AM – 12:20 PM · Chrysler 220";
    } finally {
        client.close();
    }
}
