def rows -> list[DraftRow] {
    return [
        DraftRow(title="Set up train.py", tier="Deep Work", minutes=35),
        DraftRow(title="Implement the loop", tier="Deep Work", minutes=50),
        DraftRow(title="Submit", tier="Low Energy", minutes=30, included=False)
    ];
}

test "default_title prefers the typed title, then the first line" {
    assert default_title("  Project 2 ", "whatever") == "Project 2";
    assert default_title("", "\n\n  Lab 4 report: damped pendulum\nDue Friday") == "Lab 4 report: damped pendulum";
    assert default_title("", "") == "Untitled assignment";
    long_line = "Implement logistic regression from scratch and report the learning-rate ablation results";
    shortened = default_title("", long_line);
    assert len(shortened) <= 60 and shortened.endswith("…");
}

test "summary counts every row and totals the minutes" {
    assert summary(rows()) == "3 subtasks, 1h 55m total";
    assert summary(rows()[:1]) == "1 subtask, 35m total";
    assert [r.title for r in included_rows(rows())] == ["Set up train.py", "Implement the loop"];
}

test "toggling returns a new list and leaves the original alone" {
    original = rows();

    toggled = toggle_row(original, 2);

    assert toggled[2].included and not original[2].included;
    assert toggled[0] is original[0];
}

test "edits replace one row" {
    original = rows();

    assert retitle_row(original, 0, "Write the data loader")[0].title == "Write the data loader";
    assert retier_row(original, 1, "Shallow Work")[1].tier == "Shallow Work";
    assert original[0].title == "Set up train.py" and original[1].tier == "Deep Work";
}

test "minutes are cleaned and clamped" {
    assert retime_row(rows(), 0, "45")[0].minutes == 45;
    assert retime_row(rows(), 0, "45 min")[0].minutes == 45;
    assert retime_row(rows(), 0, "0")[0].minutes == 1;
    assert retime_row(rows(), 0, "9000")[0].minutes == 480;
    assert retime_row(rows(), 0, "")[0].minutes == 35;
}
