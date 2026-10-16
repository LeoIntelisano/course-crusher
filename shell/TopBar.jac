"""Top bar (title, date, free-time and energy pills) and its mobile context strip."""

import from "@jac/runtime" { Link }
import from .status { ENERGY_LEVELS, free_text }

glob PILL: str = "items-center gap-[7px] whitespace-nowrap rounded-full border border-line-strong bg-surface px-3 py-1.5 text-[12.5px] text-text";
glob MOBILE_PILL: str = "inline-flex flex-none items-center gap-[7px] whitespace-nowrap rounded-full border border-line-strong bg-surface px-[13px] py-2 min-h-[38px] text-[13px] text-text";
glob DOT: str = "h-[7px] w-[7px] rounded-full bg-brand";
glob DOT_BUSY: str = "h-[7px] w-[7px] rounded-full bg-faint";

"""The energy pill is a real select: changing it re-plans the day."""
def:pub EnergySelect(energy: str, onEnergy: Callable[[str], None], className: str, selectId: str) -> JsxElement {
    def handle(e: ChangeEvent) {
        onEnergy(e.target.value);
    }
    <label className={className} htmlFor={selectId}>
        <span className="text-muted">Energy</span>
        <select
            id={selectId}
            aria-label="Energy"
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
