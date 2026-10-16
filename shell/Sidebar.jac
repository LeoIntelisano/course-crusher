"""Desktop sidebar: brand, primary and workspace nav, and the signed-in student."""

import from "@jac/runtime" { Link }
import from .nav { NavItem, PRIMARY_NAV, WORKSPACE_NAV, is_current }
import from ..shared.format { pluralize }

glob LINK: str = "flex items-center gap-2.5 rounded-sm px-2.5 py-2 text-[13.5px] text-nav no-underline hover:bg-ink-raised";
glob LINK_CURRENT: str = "flex items-center gap-2.5 rounded-sm px-2.5 py-2 text-[13.5px] bg-ink-raised font-semibold text-white no-underline";

def:pub SideLink(item: NavItem, path: str, count: int) -> JsxElement {
    current = is_current(item.path, path);
    <Link
        to={item.path}
        className={LINK_CURRENT if current else LINK}
        aria-current={"page" if current else None}
    >
        <span className="w-4 text-center text-[13px] opacity-85" aria-hidden="true">{item.icon}</span>
        {item.label}
        {count > 0 and <span className="ml-auto text-[11px] tabular-nums text-faint">{count}</span>}
    </Link>
}

def:pub Sidebar(path: str, initials: str, name: str, openTasks: int, courseCount: int) -> JsxElement {
    counts = {"/plan": openTasks, "/courses": courseCount};
    <aside className="hidden desk:flex flex-col bg-ink px-3.5 py-[18px] text-white">
        <div className="flex items-center gap-[9px] px-2 pt-1 pb-5">
            <span className="grid h-[22px] w-[22px] place-items-center rounded-md bg-brand text-[12px] font-bold text-white" aria-hidden="true">C</span>
            <span className="text-[14.5px] font-[650] tracking-[-0.2px]">CourseCrusher</span>
        </div>
        <nav className="flex flex-col gap-0.5" aria-label="Primary">
            {for item in PRIMARY_NAV {
                <SideLink key={item.path} item={item} path={path} count={counts.get(item.path, 0)} />
            }}
            <div className="px-2 pt-3.5 pb-1.5 text-[10.5px] uppercase tracking-[.09em] text-nav-group">Workspace</div>
            {for item in WORKSPACE_NAV {
                <SideLink key={item.path} item={item} path={path} count={0} />
            }}
        </nav>
        <div className="mt-auto border-t border-ink-raised pt-3">
            <Link to="/settings" className="flex items-center gap-[9px] rounded-sm px-2.5 py-2 no-underline hover:bg-ink-raised">
                <span className="grid h-7 w-7 flex-none place-items-center rounded-full bg-ink-line text-[11px] font-semibold text-[#e7eaee]">{initials}</span>
                <span className="flex min-w-0 flex-col leading-tight">
                    <span className="truncate text-[12.5px] text-[#e7eaee]">{name or "Your account"}</span>
                    <span className="text-[11px] text-[#7c8695]">{pluralize(courseCount, "course", "courses") + " · Settings"}</span>
                </span>
            </Link>
        </div>
    </aside>
}
