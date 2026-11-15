"""Mobile bottom tab bar: the four primary screens plus More (Connections, Settings), 48px touch targets.

Padding follows the safe-area inset so the bar clears the home indicator on notched phones.
"""

import from "@jac/runtime" { Link }
import from .nav { PRIMARY_NAV, WORKSPACE_NAV, in_workspace, is_current }

glob TAB: str = "flex min-h-[48px] flex-col items-center gap-[3px] py-[7px] text-[10.5px] font-semibold text-faint no-underline";
glob TAB_CURRENT: str = "flex min-h-[48px] flex-col items-center gap-[3px] py-[7px] text-[10.5px] font-semibold text-ink no-underline";
glob TAB_BUTTON: str = "flex min-h-[48px] flex-col items-center gap-[3px] border-0 bg-transparent py-[7px] text-[10.5px] font-semibold cursor-pointer";
glob SHEET_LINK: str = "flex min-h-[48px] items-center gap-3 rounded-md px-3 text-[14px] font-semibold text-text no-underline hover:bg-canvas";

def:pub TabBar(path: str) -> JsxElement {
    has more_open: bool = False;
    more_current = in_workspace(path);

    <>
        {more_open and <div className="fixed inset-0 z-20 bg-ink/20 desk:hidden" aria-hidden="true" onClick={lambda (e: MouseEvent) { more_open = False; }}></div>}
        {more_open and <nav
            id="more-sheet"
            aria-label="More"
            className="fixed inset-x-3 bottom-[calc(72px+env(safe-area-inset-bottom))] z-30 flex flex-col gap-1 rounded-lg border border-line bg-surface p-2 shadow-[0_12px_32px_rgba(18,21,26,0.16)] desk:hidden"
        >
            {for item in WORKSPACE_NAV {
                <Link
                    key={item.path}
                    to={item.path}
                    className={SHEET_LINK + (" bg-canvas" if is_current(item.path, path) else "")}
                    aria-current={"page" if is_current(item.path, path) else None}
                    onClick={lambda (e: MouseEvent) { more_open = False; }}
                >
                    <span className="w-5 text-center text-[16px]" aria-hidden="true">{item.icon}</span>
                    {item.label}
                </Link>
            }}
        </nav>}
        <nav
            className="fixed inset-x-0 bottom-0 z-20 grid grid-cols-5 border-t border-line bg-surface px-1 pt-1.5 pb-[calc(10px+env(safe-area-inset-bottom))] desk:hidden"
            aria-label="Primary"
        >
            {for item in PRIMARY_NAV {
                <Link
                    key={item.path}
                    to={item.path}
                    className={TAB_CURRENT if is_current(item.path, path) else TAB}
                    aria-current={"page" if is_current(item.path, path) else None}
                    onClick={lambda (e: MouseEvent) { more_open = False; }}
                >
                    <span className="text-[16px] leading-none" aria-hidden="true">{item.icon}</span>
                    {item.label}
                </Link>
            }}
            <button
                type="button"
                aria-expanded={more_open}
                aria-controls="more-sheet"
                className={TAB_BUTTON + (" text-ink" if more_current or more_open else " text-faint")}
                onClick={lambda (e: MouseEvent) { more_open = not more_open; }}
            >
                <span className="text-[16px] leading-none" aria-hidden="true">⋯</span>
                More
            </button>
        </nav>
    </>
}
