import from datetime { datetime, timedelta, timezone }
import from unittest.mock { patch }
import from jaclang.testing.testing { JacTestClient }
import from connectors.google_web_auth { WEB_CLIENT_SECRETS_ENV }
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
        with patch.dict("os.environ", {WEB_CLIENT_SECRETS_ENV: ""}) {
            today = call(client, "get_today");
        }

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

"""Add a one-step assignment approved for tomorrow at 15:00 UTC, and return that time and the task id."""
def add_approved(client: JacTestClient) -> tuple[datetime, str] {
    course = call(client, "list_courses")[0];
    tomorrow = (datetime.now(timezone.utc) + timedelta(days=1)).replace(hour=15, minute=0, second=0, microsecond=0);
    saved = call(client, "add_assignment", {
        "course_id": course["id"],
        "title": "Lab report",
        "description": "",
        "due_at": "",
        "subtasks": [subtask_draft("Outline the report", "Shallow Work", 30)],
        "approved_starts": [tomorrow.isoformat()]
    });
    assert saved["ok"], saved["error"];
    lab = [a for a in saved["courses"][0]["assignments"] if a["title"] == "Lab report"][0];
    return (tomorrow, lab["tasks"][0]["id"]);
}

test "an approved time from Breakdown stays on the plan" {
    client = seeded_client();
    try {
        (approved_at, task_id) = add_approved(client);

        item = [i for i in week_items(client) if i["task_id"] == task_id][0];

        assert datetime.fromisoformat(item["start"]) == approved_at;
        assert item["approved"];
        assert not [i for i in week_items(client) if i["task_id"] != task_id and i["approved"]];
    } finally {
        client.close();
    }
}

test "reschedule and not today release the approved time" {
    client = seeded_client();
    try {
        (approved_at, task_id) = add_approved(client);

        assert call(client, "reschedule_task", {"task_id": task_id})["ok"];
        item = [i for i in week_items(client) if i["task_id"] == task_id][0];

        assert not item["approved"];
        assert datetime.fromisoformat(item["start"]) >= approved_at + timedelta(minutes=30);
        (_, other_id) = add_approved(client);
        assert call(client, "skip_task_today", {"task_id": other_id})["ok"];
        assert not [i for i in week_items(client) if i["task_id"] == other_id][0]["approved"];
    } finally {
        client.close();
    }
}

test "preview blocks carry the start the student would approve" {
    client = seeded_client();
    try {
        result = call(client, "preview_fit", {
            "title": "Lab", "due_at": "", "subtasks": [subtask_draft("Outline", "Shallow Work", 30)]
        });

        block = result["preview"]["blocks"][0];
        assert block["placed"] and datetime.fromisoformat(block["start"]).tzinfo is not None;
    } finally {
        client.close();
    }
}

"""Add a one-step assignment approved 40 minutes ago (30 minutes long), and return its id."""
def add_ended(client: JacTestClient, title: str) -> str {
    course = call(client, "list_courses")[0];
    started = (datetime.now(timezone.utc) - timedelta(minutes=40)).replace(second=0, microsecond=0);
    saved = call(client, "add_assignment", {
        "course_id": course["id"],
        "title": title,
        "description": "",
        "due_at": "",
        "subtasks": [subtask_draft(f"{title} step", "Shallow Work", 30)],
        "approved_starts": [started.isoformat()]
    });
    assert saved["ok"], saved["error"];
    return [a for a in saved["courses"][0]["assignments"] if a["title"] == title][0]["tasks"][0]["id"];
}

def ended_ids(client: JacTestClient) -> list[str] {
    return [item["task_id"] for item in call(client, "get_week")["ended_today"]];
}

test "earlier-today blocks can be released or closed out together" {
    client = seeded_client();
    try {
        first = add_ended(client, "Reading");
        second = add_ended(client, "Quiz");
        third = add_ended(client, "Lab");
        # Past UTC 00:40 those blocks started yesterday; the view logic is covered in views.test.jac.
        if datetime.now(timezone.utc).hour >= 1 {
            assert sorted(ended_ids(client)) == sorted([first, second, third]);
        }

        assert call(client, "release_task", {"task_id": first})["ok"];
        assert call(client, "complete_tasks", {"task_ids": [second, third, "missing"]})["ok"];

        assert ended_ids(client) == [];
        week_ids = [i["task_id"] for i in week_items(client)];
        assert first in week_ids and second not in week_ids and third not in week_ids;
        assert call(client, "get_today")["open_tasks"] == 4;
    } finally {
        client.close();
    }
}

test "closing out validates its input" {
    client = seeded_client();
    try {
        assert not call(client, "complete_tasks", {"task_ids": []})["ok"];
        assert not call(client, "complete_tasks", {"task_ids": ["missing"]})["ok"];
        assert "at most" in call(client, "complete_tasks", {"task_ids": ["x"] * 51})["error"];
        assert not call(client, "release_task", {"task_id": "missing"})["ok"];
    } finally {
        client.close();
    }
}
