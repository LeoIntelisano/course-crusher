"""Small presentational pieces reused across screens."""

import from .format { tier_key }
import from .styles { CARD_ASIDE, CARD_HEADER, CARD_TITLE, CHIP_PLAIN, CHIP_WARN, TIER_CHIP, TIER_DOT }

glob NOTICE_TONES: dict[str, str] = {
    "error": "rounded-md border border-transparent bg-danger-bg px-[13px] py-[11px] text-[12.5px] font-semibold text-danger",
    "success": "rounded-md border border-transparent bg-brand-bg px-[13px] py-[11px] text-[12.5px] font-semibold text-brand",
    "info": "rounded-md border border-line bg-canvas px-[13px] py-[11px] text-[12.5px] text-body"
};

"""Tier is always shown with its label, never by colour alone."""
def:pub TierChip(tier: str) -> JsxElement {
    key = tier_key(tier);
    <span className={TIER_CHIP[key]}><span className={TIER_DOT[key]} aria-hidden="true"></span>{tier}</span>
}

def:pub PlainChip(text: str) -> JsxElement {
    <span className={CHIP_PLAIN}>{text}</span>
}

def:pub WarnChip(text: str) -> JsxElement {
    <span className={CHIP_WARN}>{text}</span>
}

def:pub CardHeader(title: str, titleId: str, aside: str = "", children: any = None) -> JsxElement {
    <div className={CARD_HEADER}>
        <h2 id={titleId} className={CARD_TITLE}>{title}</h2>
        {children}
        {aside and <span className={CARD_ASIDE}>{aside}</span>}
    </div>
}

"""An inline message. Errors are announced immediately; other tones politely."""
def:pub Notice(tone: str, message: str) -> JsxElement {
    if not message {
        return <></>;
    }
    role = "alert" if tone == "error" else "status";
    <p role={role} className={NOTICE_TONES.get(tone, NOTICE_TONES["info"])}>{message}</p>
}

def:pub EmptyState(title: str, detail: str, children: any = None) -> JsxElement {
    <div className="px-5 py-[38px] text-center text-faint">
        <div className="text-[14px] font-[650] text-muted">{title}</div>
        <div className="mt-[5px] text-[12.5px]">{detail}</div>
        {children}
    </div>
}
