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
