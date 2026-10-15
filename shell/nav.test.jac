test "the root path only matches Today" {
    assert is_current("/", "/");
    assert not is_current("/", "/plan");
}

test "sub-pages count as their parent screen" {
    assert is_current("/connections", "/connections/google/callback");
    assert not is_current("/connections", "/connectionsx");
}

test "titles follow the current screen" {
    assert title_for("/") == "Today";
    assert title_for("/breakdown") == "Breakdown";
    assert title_for("/connections/google/callback") == "Connections";
    assert title_for("/nowhere") == "CourseCrusher";
}

test "the tab bar holds the four primary screens" {
    assert [item.label for item in PRIMARY_NAV if item.in_tab_bar] == ["Today", "Plan", "Breakdown", "Courses"];
    assert [item.label for item in WORKSPACE_NAV] == ["Connections", "Settings"];
}
