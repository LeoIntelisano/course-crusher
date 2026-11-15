"""Top bar (title, date, free-time and energy pills) and its mobile context strip."""

import from "@jac/runtime" { Link }
import from .status { ENERGY_HELP, ENERGY_LEVELS, free_text }

glob PILL: str = "items-center gap-[7px] whitespace-nowrap rounded-full border border-line-strong bg-surface px-3 py-1.5 text-[12.5px] text-text";
glob MOBILE_PILL: str = "inline-flex flex-none items-center gap-[7px] whitespace-nowrap rounded-full border border-line-strong bg-surface px-[13px] py-2 min-h-[38px] text-[13px] text-text";
glob DOT: str = "h-[7px] w-[7px] rounded-full bg-brand";
glob DOT_BUSY: str = "h-[7px] w-[7px] rounded-full bg-faint";

"""The energy pill is a real select: changing it re-plans the rest of today.

The ? button explains what each level does to the plan.
"""
def:pub EnergySelect(energy: str, onEnergy: Callable[[str], None], className: str, selectId: str) -> JsxElement {
    has helping: bool = False;
    help_id = selectId + "-help";

    def handle(e: ChangeEvent) {
        onEnergy(e.target.value);
    }

    <span className={className + " relative"}>
        <label className="inline-flex cursor-pointer items-center gap-[7px]" htmlFor={selectId}>
            <span className="text-muted">Energy</span>
            <select
                id={selectId}
                aria-label="Energy"
                aria-describedby={help_id if helping else None}
                value={energy}
                onChange={handle}
                className="cursor-pointer appearance-none border-0 bg-transparent p-0 font-semibold text-text"
            >
                {for level in ENERGY_LEVELS {
                    <option key={level} value={level}>{level}</option>
                }}
            </select>
            <span className="text-[10px] text-faint" aria-hidden="true">▾</span>
        </label>
        <button
            type="button"
            aria-label="What the energy levels do"
            aria-expanded={helping}
            aria-controls={help_id}
            className="grid h-[18px] w-[18px] place-items-center rounded-full border border-line-strong bg-transparent p-0 text-[10.5px] font-bold text-muted cursor-pointer hover:border-ink hover:text-ink"
            onClick={lambda (e: MouseEvent) { helping = not helping; }}
        >
            ?
        </button>
        {helping and <div
            id={help_id}
            role="note"
            className="fixed inset-x-3 top-[112px] z-40 whitespace-normal rounded-md border border-line bg-surface p-3 text-left shadow-[0_12px_32px_rgba(18,21,26,0.16)] desk:absolute desk:inset-x-auto desk:right-0 desk:top-[calc(100%+8px)] desk:w-[300px]"
        >
            <div className="mb-1 text-[11px] font-[650] uppercase tracking-[.08em] text-faint">How energy changes today's plan</div>
            {for level in ENERGY_LEVELS {
                <div key={level} className="py-1.5">
                    <div className={"text-[12.5px] font-semibold " + ("text-brand" if level == energy else "text-text")}>{level + (" · now" if level == energy else "")}</div>
                    <div className="mt-0.5 text-[12px] leading-[1.45] text-muted">{ENERGY_HELP[level]}</div>
                </div>
            }}
            <div className="mt-1 text-[11.5px] text-faint">Deep Work due today is never held back.</div>
        </div>}
    </span>
}

def:pub TopBar(
    title: str,
    dateLabel: str,
    freeState: str,
    freeUntil: str,
    freeMinutes: int,
    energy: str,
    initials: str,
    ready: bool,
    onEnergy: Callable[[str], None]
) -> JsxElement {
    <header className="flex h-[54px] flex-none items-center gap-2.5 border-b border-line bg-surface px-3.5 desk:h-[60px] desk:gap-3.5 desk:px-[22px]">
        <h1 id="screen-title" className="m-0 text-[16px] font-[650] tracking-[-0.25px] desk:text-[17px]">{title}</h1>
        <span className="hidden text-[13px] text-muted desk:inline">{dateLabel}</span>
        <span className="flex-1"></span>
        {ready and <span className={"hidden desk:inline-flex " + PILL}>
            <span className={DOT if freeState == "free" else DOT_BUSY} aria-hidden="true"></span>
            {free_text(freeState, freeUntil, freeMinutes, False)}
        </span>}
        {ready and <EnergySelect energy={energy} onEnergy={onEnergy} className={"hidden desk:inline-flex " + PILL} selectId="energy-desktop" />}
        <Link
            to="/settings"
            aria-label="Settings"
            className="grid h-[30px] w-[30px] place-items-center rounded-full bg-[#dfe3e9] text-[11.5px] font-[650] text-[#4a5361] no-underline"
        >
            {initials}
        </Link>
    </header>
}

def:pub MobileContext(
    freeState: str, freeUntil: str, freeMinutes: int, energy: str, onEnergy: Callable[[str], None]
) -> JsxElement {
    <div className="flex gap-2 overflow-x-auto border-b border-line bg-surface px-3.5 py-[11px] desk:hidden">
        <span className={MOBILE_PILL}>
            <span className={DOT if freeState == "free" else DOT_BUSY} aria-hidden="true"></span>
            {free_text(freeState, freeUntil, freeMinutes, True)}
        </span>
        <EnergySelect energy={energy} onEnergy={onEnergy} className={MOBILE_PILL} selectId="energy-mobile" />
    </div>
}
