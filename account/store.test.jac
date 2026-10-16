import from shared.api_testing { call, sign_up, signed_in_client }

def valid_profile(overrides: dict[str, any] | None = None) -> dict[str, any] {
    return {
        "display_name": "Varshini Anbu",
        "timezone": "America/Los_Angeles",
        "day_start": "09:00",
        "day_end": "23:00",
        "deep_work_cutoff": "21:30",
        "buffer_minutes": 15,
        "min_slot_minutes": 20,
        **(overrides or {})
    };
}

test "setup_account stores the name and time zone from signup" {
    client = signed_in_client();
    try {
        result = call(client, "setup_account", {"display_name": "  Varshini   Anbu ", "timezone": "America/Chicago"});
        bad_zone = call(client, "setup_account", {"display_name": "V", "timezone": "Nowhere/Land"});

        assert result["ok"];
        assert result["profile"]["display_name"] == "Varshini Anbu";
        assert result["profile"]["initials"] == "VA";
        assert result["profile"]["timezone"] == "America/Chicago";
        assert not bad_zone["ok"] and "Unknown time zone" in bad_zone["error"];
        assert call(client, "get_profile")["display_name"] == "Varshini Anbu";
    } finally {
        client.close();
    }
}

test "save_profile updates every planning setting" {
    client = signed_in_client();
    try {
        result = call(client, "save_profile", valid_profile());

        assert result["ok"], result["error"];
        saved = call(client, "get_profile");
        assert (saved["day_start"], saved["day_end"], saved["deep_work_cutoff"]) == ("09:00", "23:00", "21:30");
        assert (saved["buffer_minutes"], saved["min_slot_minutes"], saved["timezone"]) == (15, 20, "America/Los_Angeles");
    } finally {
        client.close();
    }
}

test "save_profile rejects settings the planner can't use and keeps the old ones" {
    client = signed_in_client();
    try {
        cases = [
            ({"day_start": "22:00", "day_end": "08:00"}, "Deep Work cutoff must fall inside your day"),
            ({"day_start": "8am"}, "Use 24-hour HH:MM"),
            ({"buffer_minutes": 90}, "buffer between 0 and 60"),
            ({"min_slot_minutes": 1}, "shortest slot must be between 5 and 120"),
            ({"deep_work_cutoff": "23:30"}, "cutoff must fall inside your day"),
            ({"timezone": "Atlantis"}, "Unknown time zone"),
            ({"display_name": "x" * 81}, "under 80 characters")
        ];
        for (overrides, message) in cases {
            result = call(client, "save_profile", valid_profile(overrides));
            assert not result["ok"], f"{overrides} was accepted";
            assert message in result["error"], f"{overrides}: {result['error']}";
        }
        assert call(client, "get_profile")["day_start"] == "08:00";
    } finally {
        client.close();
    }
}

test "set_energy accepts only the three levels" {
    client = signed_in_client();
    try {
        assert call(client, "set_energy", {"energy": "Low"})["profile"]["energy"] == "Low";
        rejected = call(client, "set_energy", {"energy": "Exhausted"});

        assert not rejected["ok"] and "High, Medium, Low" in rejected["error"];
        assert call(client, "get_profile")["energy"] == "Low";
    } finally {
        client.close();
    }
}

test "protected hours can be added, listed in order and removed" {
    client = signed_in_client();
    try {
        call(client, "add_protected_hours", {"label": "Dinner & gym", "start": "17:00", "end": "19:00"});
        result = call(client, "add_protected_hours", {"label": "Morning run", "start": "07:00", "end": "07:45"});

        assert [(p["label"], p["start"]) for p in result["profile"]["protected"]] == [
            ("Morning run", "07:00"), ("Dinner & gym", "17:00")
        ];
        removed = call(client, "remove_protected_hours", {"block_id": result["profile"]["protected"][0]["id"]});
        assert [p["label"] for p in removed["profile"]["protected"]] == ["Dinner & gym"];
        missing = call(client, "remove_protected_hours", {"block_id": "not-a-real-id"});
        assert not missing["ok"] and "no longer exists" in missing["error"];
    } finally {
        client.close();
    }
}

test "protected hours are validated" {
    client = signed_in_client();
    try {
        cases = [
            ({"label": "", "start": "17:00", "end": "19:00"}, "Give the protected time a name"),
            ({"label": "Dinner", "start": "19:00", "end": "17:00"}, "end after it starts"),
            ({"label": "Dinner", "start": "dinner", "end": "19:00"}, "Use 24-hour HH:MM"),
            ({"label": "x" * 61, "start": "17:00", "end": "19:00"}, "under 60 characters"),
            ({"label": "Dinner", "start": "17:00+05:00", "end": "19:00"}, "Use 24-hour HH:MM")
        ];
        for (payload, message) in cases {
            result = call(client, "add_protected_hours", payload);
            assert not result["ok"] and message in result["error"], f"{payload}: {result}";
        }
    } finally {
        client.close();
    }
}

test "one student's settings are invisible to another" {
    client = signed_in_client("first@example.com");
    try {
        call(client, "setup_account", {"display_name": "First", "timezone": "UTC"});
        added = call(client, "add_protected_hours", {"label": "Practice", "start": "16:00", "end": "18:00"});
        block_id = added["profile"]["protected"][0]["id"];

        sign_up(client, "second@example.com");
        second = call(client, "get_profile");
        steal = call(client, "remove_protected_hours", {"block_id": block_id});

        assert second["display_name"] == "" and second["protected"] == [];
        assert not steal["ok"];
    } finally {
        client.close();
    }
}

test "protected hours are capped per student" {
    client = signed_in_client();
    try {
        for n in range(10) {
            added = call(client, "add_protected_hours", {"label": f"Block {n}", "start": "06:00", "end": "06:30"});
            assert added["ok"], added["error"];
        }
        over = call(client, "add_protected_hours", {"label": "One more", "start": "06:00", "end": "06:30"});

        assert not over["ok"] and "up to 10 protected times" in over["error"];
    } finally {
        client.close();
    }
}
