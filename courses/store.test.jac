import from jaclang.testing.testing { JacTestClient }
import from shared.api_testing { call, sign_up, signed_in_client }

def subtask_draft(title: str, tier: str = "Deep Work", minutes: int = 30) -> dict[str, any] {
    return {"title": title, "tier": tier, "estimated_duration": minutes};
}

def create_course(client: JacTestClient, code: str, name: str = "") -> dict[str, any] {
    result = call(client, "add_course", {"code": code, "name": name});
    assert result["ok"], result["error"];
    return [c for c in result["courses"] if c["code"] == code.upper()][0];
}

def create_assignment(client: JacTestClient, course_id: str, subtasks: list[dict[str, any]], due_at: str = "2026-10-21T23:59") -> dict[str, any] {
    return call(client, "add_assignment", {
        "course_id": course_id,
        "title": "Project 2",
        "description": "Implement logistic regression from scratch.",
        "due_at": due_at,
        "subtasks": subtasks
    });
}

test "courses are added, upper-cased, sorted and de-duplicated" {
    client = signed_in_client();
    try {
        create_course(client, "phys 240", "Physics");
        create_course(client, "EECS 445", "Machine Learning");
        duplicate = call(client, "add_course", {"code": "eecs 445", "name": ""});
        empty = call(client, "add_course", {"code": "   ", "name": ""});
        too_long = call(client, "add_course", {"code": "X" * 21, "name": ""});

        listed = call(client, "list_courses");
        assert [(c["code"], c["name"]) for c in listed] == [("EECS 445", "Machine Learning"), ("PHYS 240", "Physics")];
        assert not duplicate["ok"] and "already have EECS 445" in duplicate["error"];
        assert not empty["ok"] and "Course code is required" in empty["error"];
        assert not too_long["ok"] and "under 20 characters" in too_long["error"];
    } finally {
        client.close();
    }
}

test "class meetings are validated and summarized" {
    client = signed_in_client();
    try {
        course = create_course(client, "EECS 445");
        added = call(client, "add_meeting", {
            "course_id": course["id"], "kind": "Lecture", "weekdays": [2, 0, 0],
            "start": "11:00", "end": "12:20", "location": "Chrysler 220"
        });
        no_days = call(client, "add_meeting", {
            "course_id": course["id"], "kind": "Lab", "weekdays": [], "start": "14:00", "end": "16:00", "location": ""
        });
        bad_day = call(client, "add_meeting", {
            "course_id": course["id"], "kind": "Lab", "weekdays": [7], "start": "14:00", "end": "16:00", "location": ""
        });
        backwards = call(client, "add_meeting", {
            "course_id": course["id"], "kind": "Lab", "weekdays": [1], "start": "16:00", "end": "14:00", "location": ""
        });

        meeting = added["courses"][0]["meetings"][0];
        assert meeting["weekdays"] == [0, 2];
        assert meeting["summary"] == "Mon Wed 11:00 AM – 12:20 PM · Chrysler 220";
        assert not no_days["ok"] and "at least one weekday" in no_days["error"];
        assert not bad_day["ok"];
        assert not backwards["ok"] and "end after it starts" in backwards["error"];
        removed = call(client, "remove_meeting", {"meeting_id": meeting["id"]});
        assert removed["courses"][0]["meetings"] == [];
    } finally {
        client.close();
    }
}

test "courses, class times and open subtasks are capped per student" {
    client = signed_in_client();
    try {
        for n in range(20) {
            assert call(client, "add_course", {"code": f"C{n}", "name": ""})["ok"];
        }
        too_many_courses = call(client, "add_course", {"code": "C20", "name": ""});
        course_id = call(client, "list_courses")[0]["id"];
        for n in range(10) {
            assert call(client, "add_meeting", {
                "course_id": course_id, "kind": "Lecture", "weekdays": [n % 7],
                "start": "09:00", "end": "10:00", "location": ""
            })["ok"];
        }
        too_many_meetings = call(client, "add_meeting", {
            "course_id": course_id, "kind": "Lab", "weekdays": [0], "start": "11:00", "end": "12:00", "location": ""
        });
        for n in range(16) {
            assert create_assignment(client, course_id, [subtask_draft(f"Step {k}") for k in range(25)])["ok"];
        }
        too_many_tasks = create_assignment(client, course_id, [subtask_draft("One more")]);

        assert not too_many_courses["ok"] and "up to 20 courses" in too_many_courses["error"];
        assert not too_many_meetings["ok"] and "up to 10 class times" in too_many_meetings["error"];
        assert not too_many_tasks["ok"] and "capped at 400 open subtasks" in too_many_tasks["error"];
    } finally {
        client.close();
    }
}

test "a class time with a UTC offset is rejected, not a server error" {
    client = signed_in_client();
    try {
        course = create_course(client, "EECS 445");
        result = call(client, "add_meeting", {
            "course_id": course["id"], "kind": "Lab", "weekdays": [1], "start": "14:00+02:00", "end": "16:00", "location": ""
        });

        assert not result["ok"] and "Use 24-hour HH:MM" in result["error"];
    } finally {
        client.close();
    }
}

test "an assignment saves its confirmed subtasks in order" {
    client = signed_in_client();
    try {
        course = create_course(client, "EECS 445");
        result = create_assignment(client, course["id"], [
            subtask_draft("Set up train.py", "Deep Work", 35),
            subtask_draft("Run the ablation", "Shallow Work", 25),
            subtask_draft("Submit to Canvas", "Low Energy", 10)
        ]);

        assert result["ok"], result["error"];
        saved = result["courses"][0];
        assignment = saved["assignments"][0];
        assert assignment["due_at"] == "2026-10-21T23:59:00-04:00";
        assert [(t["order"], t["title"], t["tier"]) for t in assignment["tasks"]] == [
            (1, "Set up train.py", "Deep Work"), (2, "Run the ablation", "Shallow Work"), (3, "Submit to Canvas", "Low Energy")
        ];
        assert (assignment["open_minutes"], saved["open_tasks"], saved["open_minutes"]) == (70, 3, 70);
    } finally {
        client.close();
    }
}

test "add_assignment rejects bad subtasks and saves nothing" {
    client = signed_in_client();
    try {
        course = create_course(client, "EECS 445");
        cases = [
            ([], "Select at least one subtask"),
            ([subtask_draft("  ")], "Subtask 1 title is required"),
            ([subtask_draft("Ok"), subtask_draft("Bad", "Medium Work")], "Subtask 2 has an unknown tier"),
            ([subtask_draft("Zero", minutes=0)], "needs 1 to 480 minutes"),
            ([subtask_draft("Huge", minutes=481)], "needs 1 to 480 minutes"),
            ([subtask_draft(f"Step {n}") for n in range(26)], "at most 25 subtasks")
        ];
        for (subtasks, message) in cases {
            result = create_assignment(client, course["id"], subtasks);
            assert not result["ok"] and message in result["error"], f"{message}: {result['error']}";
        }
        bad_due = create_assignment(client, course["id"], [subtask_draft("Ok")], due_at="whenever");
        far_due = create_assignment(client, course["id"], [subtask_draft("Ok")], due_at="9999-12-31T23:59+00:00");
        assert not bad_due["ok"] and "Due date" in bad_due["error"];
        assert not far_due["ok"] and "within the next five years" in far_due["error"];
        no_course = call(client, "add_assignment", {
            "course_id": "missing", "title": "T", "description": "", "due_at": "", "subtasks": [subtask_draft("Ok")]
        });
        assert not no_course["ok"];
        assert call(client, "list_courses")[0]["assignments"] == [];
    } finally {
        client.close();
    }
}

test "completing a subtask updates the course totals" {
    client = signed_in_client();
    try {
        course = create_course(client, "EECS 445");
        saved = create_assignment(client, course["id"], [subtask_draft("One", minutes=20), subtask_draft("Two", minutes=40)]);
        first = saved["courses"][0]["assignments"][0]["tasks"][0];

        done = call(client, "set_task_done", {"task_id": first["id"], "done": True});
        undone = call(client, "set_task_done", {"task_id": first["id"], "done": False});

        assert done["courses"][0]["assignments"][0]["tasks"][0]["done"];
        assert done["courses"][0]["open_minutes"] == 40;
        assert done["courses"][0]["assignments"][0]["done_count"] == 1;
        assert undone["courses"][0]["open_minutes"] == 60;
    } finally {
        client.close();
    }
}

test "removing a course removes its assignments and subtasks" {
    client = signed_in_client();
    try {
        course = create_course(client, "EECS 445");
        create_assignment(client, course["id"], [subtask_draft("One")]);
        task_id = call(client, "list_courses")[0]["assignments"][0]["tasks"][0]["id"];

        removed = call(client, "remove_course", {"course_id": course["id"]});
        orphan = call(client, "set_task_done", {"task_id": task_id, "done": True});

        assert removed["ok"] and removed["courses"] == [];
        assert not orphan["ok"];
        assert call(client, "get_today")["open_tasks"] == 0;
    } finally {
        client.close();
    }
}

test "removing an assignment keeps the course" {
    client = signed_in_client();
    try {
        course = create_course(client, "EECS 445");
        saved = create_assignment(client, course["id"], [subtask_draft("One")]);

        removed = call(client, "remove_assignment", {"assignment_id": saved["courses"][0]["assignments"][0]["id"]});

        assert removed["ok"] and removed["courses"][0]["assignments"] == [];
        assert not call(client, "remove_assignment", {"assignment_id": "gone"})["ok"];
    } finally {
        client.close();
    }
}

test "students cannot see or change each other's courses" {
    client = signed_in_client("owner@example.com");
    try {
        course = create_course(client, "EECS 445");
        create_assignment(client, course["id"], [subtask_draft("Private step")]);
        task_id = call(client, "list_courses")[0]["assignments"][0]["tasks"][0]["id"];

        sign_up(client, "intruder@example.com");
        listed = call(client, "list_courses");
        delete_attempt = call(client, "remove_course", {"course_id": course["id"]});
        complete_attempt = call(client, "set_task_done", {"task_id": task_id, "done": True});

        assert listed == [];
        assert not delete_attempt["ok"] and not complete_attempt["ok"];
    } finally {
        client.close();
    }
}
