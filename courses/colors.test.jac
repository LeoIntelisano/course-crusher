test "the first colors follow the palette order" {
    assert next_color([]) == "indigo";
    assert next_color(["indigo"]) == "teal";
    assert next_color(["indigo", "teal", "amber"]) == "rose";
}

test "after a full round the least-used color comes next" {
    assert next_color(PALETTE) == "indigo";
    assert next_color(PALETTE + ["indigo", "teal"]) == "amber";
    assert next_color(["teal", "teal"]) == "indigo";
}

test "only palette colors are valid" {
    assert is_course_color("rose");
    assert not is_course_color("");
    assert not is_course_color("#ff0000");
    assert not is_course_color("Rose");
}

test "fill_colors keeps set colors and fills gaps without repeats" {
    assert fill_colors(["", "", ""]) == ["indigo", "teal", "amber"];
    assert fill_colors(["teal", "", "bogus"]) == ["teal", "indigo", "amber"];
    assert fill_colors([]) == [];
}
