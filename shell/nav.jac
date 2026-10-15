"""The app's screens, in sidebar order. The first four also appear in the mobile tab bar."""

obj NavItem {
    has path: str;
    has label: str;
    has icon: str;
    has in_tab_bar: bool;
}

glob PRIMARY_NAV: list[NavItem] = [
    NavItem(path="/", label="Today", icon="◈", in_tab_bar=True),
    NavItem(path="/plan", label="Plan", icon="▤", in_tab_bar=True),
    NavItem(path="/breakdown", label="Breakdown", icon="✳", in_tab_bar=True),
    NavItem(path="/courses", label="Courses", icon="◇", in_tab_bar=True)
];

glob WORKSPACE_NAV: list[NavItem] = [
    NavItem(path="/connections", label="Connections", icon="⇄", in_tab_bar=False),
    NavItem(path="/settings", label="Settings", icon="⚙", in_tab_bar=False)
];

"""Whether `path` belongs to the screen at `item_path` (sub-pages count as their parent)."""
def is_current(item_path: str, path: str) -> bool {
    if item_path == "/" {
        return path == "/";
    }
    return path == item_path or path.startswith(item_path + "/");
}

def title_for(path: str) -> str {
    for item in PRIMARY_NAV + WORKSPACE_NAV {
        if is_current(item.path, path) {
            return item.label;
        }
    }
    return "CourseCrusher";
}
