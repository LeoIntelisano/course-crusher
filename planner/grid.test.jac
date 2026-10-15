test "minutes convert to pixels at 44px an hour" {
    assert minutes_to_px(60) == 44;
    assert minutes_to_px(30) == 22;
    assert grid_height(480, 1320) == 14 * 44;
    assert grid_height(600, 480) == 0;
}

test "hour marks run from the top of the grid to the hour before its end" {
    assert hour_marks(480, 1320) == [8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21];
    assert hour_marks(0, 120) == [0, 1];
}

test "hour labels use 12-hour time" {
    assert [hour_text(h) for h in [0, 9, 12, 13, 23]] == ["12 AM", "9 AM", "12 PM", "1 PM", "11 PM"];
}

test "items are placed by time and lane" {
    box = item_box(660, 740, 480, 1, 2);

    assert box["top"] == "132px";
    assert box["height"] == "56px";
    assert box["left"] == "50.0%";
    assert box["width"] == "calc(50.0% - 3px)";
}

test "short items keep a readable minimum height" {
    assert item_box(600, 605, 480, 0, 1)["height"] == "18px";
    assert item_box(600, 660, 480, 0, 0)["width"] == "calc(100.0% - 3px)";
}

test "the now line is hidden off the grid" {
    assert now_offset(750, 480, 1320) == 198;
    assert now_offset(300, 480, 1320) == -1;
    assert now_offset(-1, 480, 1320) == -1;
}
