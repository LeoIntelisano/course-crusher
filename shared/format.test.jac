test "format_minutes reads naturally at every scale" {
    assert format_minutes(0) == "0m";
    assert format_minutes(45) == "45m";
    assert format_minutes(60) == "1h";
    assert format_minutes(185) == "3h 5m";
}

test "format_span switches to days past 24 hours" {
    assert format_span(210) == "3h 30m";
    assert format_span(1440) == "1d";
    assert format_span(4514) == "3d 3h";
}

test "tier_key maps tiers to the wireframe's CSS keys" {
    assert tier_key("Deep Work") == "deep";
    assert tier_key("Shallow Work") == "shallow";
    assert tier_key("Low Energy") == "low";
    assert tier_key("Medium Work") == "shallow";
}

test "pluralize picks the noun by count" {
    assert pluralize(1, "subtask", "subtasks") == "1 subtask";
    assert pluralize(0, "subtask", "subtasks") == "0 subtasks";
    assert pluralize(5, "subtask", "subtasks") == "5 subtasks";
}

test "initials uses at most two names" {
    assert initials("Varshini Anbu") == "VA";
    assert initials("  leo   r  intelisano ") == "LR";
    assert initials("Ada") == "A";
    assert initials("   ") == "?";
}

test "countdown_text pads minutes and seconds" {
    assert countdown_text(3017) == "50:17";
    assert countdown_text(65) == "01:05";
    assert countdown_text(0) == "00:00";
    assert countdown_text(-5) == "00:00";
}
