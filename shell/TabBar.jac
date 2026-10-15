"""Mobile bottom tab bar: the four primary screens, 48px touch targets."""

import from "@jac/runtime" { Link }
import from .nav { PRIMARY_NAV, is_current }

glob TAB: str = "flex min-h-[48px] flex-col items-center gap-[3px] py-[7px] text-[10.5px] font-semibold text-faint no-underline";
glob TAB_CURRENT: str = "flex min-h-[48px] flex-col items-center gap-[3px] py-[7px] text-[10.5px] font-semibold text-ink no-underline";

def:pub TabBar(path: str) -> JsxElement {
    <nav
        className="fixed inset-x-0 bottom-0 z-20 grid grid-cols-4 border-t border-line bg-surface px-1 pt-1.5 pb-2.5 desk:hidden"
        aria-label="Primary"
    >
        {for item in PRIMARY_NAV {
            <Link
                key={item.path}
                to={item.path}
                className={TAB_CURRENT if is_current(item.path, path) else TAB}
                aria-current={"page" if is_current(item.path, path) else None}
            >
                <span className="text-[16px] leading-none" aria-hidden="true">{item.icon}</span>
                {item.label}
            </Link>
        }}
    </nav>
}
