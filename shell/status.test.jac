test "free time reads as the wireframe's pills" {
    assert free_text("free", "2:00 PM", 85, False) == "Free until 2:00 PM";
    assert free_text("free", "2:00 PM", 85, True) == "Free 1h 25m";
}

test "busy and finished days say so" {
    assert free_text("busy", "4:00 PM", 30, False) == "Busy until 4:00 PM";
    assert free_text("busy", "4:00 PM", 30, True) == "Busy until 4:00 PM";
    assert free_text("done", "", 0, False) == "Day's done";
}

test "energy levels are offered high to low" {
    assert ENERGY_LEVELS == ["High", "Medium", "Low"];
}

test "every level is explained" {
    assert sorted(ENERGY_HELP.keys()) == sorted(ENERGY_LEVELS);
    assert "90 minutes" in ENERGY_HELP["Medium"];
}

test "the energy notice says what moved off today" {
    assert energy_notice("Low", ["a", "b", "c"], ["c"]) == "Energy set to Low: moved 2 blocks off today.";
    assert energy_notice("Medium", ["a", "b"], ["b"]) == "Energy set to Medium: moved 1 block off today.";
}

test "the energy notice says what moved in" {
    assert energy_notice("High", ["c"], ["a", "c"]) == "Energy set to High: 1 block moved into today.";
    assert energy_notice("Medium", ["a"], ["b"]) == "Energy set to Medium: moved 1 block off today and 1 block in.";
}

test "an unchanged day says so" {
    assert energy_notice("Low", [], []) == "Energy set to Low. Today's plan didn't need to change.";
    assert energy_notice("High", ["a"], ["a"]) == "Energy set to High. Today's plan didn't need to change.";
}
