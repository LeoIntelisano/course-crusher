"""Tailwind class strings shared by every screen.

Kept as whole literals (never assembled from fragments) so Tailwind's scanner
finds each class. Tier lookups go through `shared.format.tier_key`.
"""

glob CARD: str = "bg-surface border border-line rounded-lg";
glob CARD_STACK: str = "flex flex-col gap-[13px] min-w-0";
glob CARD_HEADER: str = "flex items-center gap-2.5 px-4 pt-3.5";
glob CARD_TITLE: str = "m-0 text-[13.5px] desk:text-[13px] font-[650] tracking-[-0.1px]";
glob CARD_ASIDE: str = "ml-auto text-[11.5px] text-faint";
glob COLUMNS: str = "grid grid-cols-1 gap-3.5 items-start desk:grid-cols-[minmax(0,1fr)_344px] desk:gap-[18px]";

glob BUTTON: str = "inline-flex items-center justify-center gap-2 rounded-sm border border-line-strong bg-surface px-[15px] py-[9px] text-[13px] font-semibold tracking-[-0.1px] text-text cursor-pointer disabled:opacity-60 disabled:cursor-progress";
glob BUTTON_PRIMARY: str = "inline-flex items-center justify-center gap-2 rounded-sm border border-ink bg-ink px-[15px] py-[9px] text-[13px] font-semibold tracking-[-0.1px] text-white cursor-pointer disabled:opacity-60 disabled:cursor-progress";
glob BUTTON_GHOST: str = "inline-flex items-center justify-center gap-2 rounded-sm border border-transparent bg-transparent px-[15px] py-[9px] text-[13px] font-medium text-muted cursor-pointer disabled:opacity-60";
glob BUTTON_DANGER: str = "inline-flex items-center justify-center gap-2 rounded-sm border border-line-strong bg-surface px-3 py-1.5 text-[12px] font-semibold text-danger cursor-pointer disabled:opacity-60";
glob BUTTON_SMALL: str = "inline-flex items-center justify-center gap-1.5 rounded-sm border border-line-strong bg-surface px-3 py-1.5 text-[12px] font-semibold text-text cursor-pointer disabled:opacity-60";

glob LABEL: str = "block text-[12px] font-[650] text-text";
glob FIELD: str = "block w-full mt-[7px] rounded-sm border border-line-strong bg-surface px-3 py-2.5 text-[16px] desk:text-[13.5px] leading-normal text-text placeholder:text-faint aria-invalid:border-danger";
glob FIELD_INLINE: str = "rounded-sm border border-line-strong bg-surface px-3 py-2 text-[16px] desk:text-[13.5px] leading-normal text-text";
glob TEXTAREA: str = "block w-full min-h-[112px] mt-[7px] resize-y rounded-sm border border-line-strong bg-surface px-3 py-[11px] text-[16px] desk:text-[13.5px] leading-normal text-text placeholder:text-faint aria-invalid:border-danger";
glob HINT: str = "mt-[7px] mb-0 text-[11.5px] text-muted";
glob ERROR_TEXT: str = "mt-[7px] mb-0 text-[12px] font-semibold text-danger";

glob CHIP_PLAIN: str = "inline-flex items-center gap-1.5 rounded-full border border-line bg-canvas px-2.5 py-1 text-[11.5px] font-semibold text-muted";
glob CHIP_WARN: str = "inline-flex items-center gap-1.5 rounded-full border border-transparent bg-danger-bg px-2.5 py-1 text-[11.5px] font-semibold text-danger";

glob TIER_CHIP: dict[str, str] = {
    "deep": "inline-flex items-center gap-1.5 rounded-full border border-transparent bg-deep-bg px-2.5 py-1 text-[11.5px] font-semibold text-deep",
    "shallow": "inline-flex items-center gap-1.5 rounded-full border border-transparent bg-shallow-bg px-2.5 py-1 text-[11.5px] font-semibold text-shallow",
    "low": "inline-flex items-center gap-1.5 rounded-full border border-transparent bg-low-bg px-2.5 py-1 text-[11.5px] font-semibold text-low"
};

glob TIER_DOT: dict[str, str] = {
    "deep": "inline-block w-[7px] h-[7px] rounded-full bg-deep",
    "shallow": "inline-block w-[7px] h-[7px] rounded-full bg-shallow",
    "low": "inline-block w-[7px] h-[7px] rounded-full bg-low"
};

glob ROW_DOT: dict[str, str] = {
    "deep": "w-[9px] h-[9px] flex-none rounded-full mt-[5px] desk:mt-0 bg-deep",
    "shallow": "w-[9px] h-[9px] flex-none rounded-full mt-[5px] desk:mt-0 bg-shallow",
    "low": "w-[9px] h-[9px] flex-none rounded-full mt-[5px] desk:mt-0 bg-low"
};

glob TIER_BAR: dict[str, str] = {
    "deep": "block h-full rounded-full bg-deep",
    "shallow": "block h-full rounded-full bg-shallow",
    "low": "block h-full rounded-full bg-low",
    "risk": "block h-full rounded-full bg-danger"
};

glob BLOCK: dict[str, str] = {
    "event": "rounded-sm border border-line bg-fixed-bg px-[9px] py-1.5 text-[11.5px] leading-[1.3] text-fixed",
    "busy": "rounded-sm border border-line bg-fixed-bg px-[9px] py-1.5 text-[11.5px] leading-[1.3] text-fixed",
    "protected": "rounded-sm border border-dashed border-line-strong bg-transparent px-[9px] py-1.5 text-[11.5px] leading-[1.3] text-faint",
    "deep": "rounded-sm border border-deep-line bg-deep-bg px-[9px] py-1.5 text-[11.5px] leading-[1.3] text-deep",
    "shallow": "rounded-sm border border-shallow-line bg-shallow-bg px-[9px] py-1.5 text-[11.5px] leading-[1.3] text-shallow",
    "low": "rounded-sm border border-low-line bg-low-bg px-[9px] py-1.5 text-[11.5px] leading-[1.3] text-low"
};

# Course colors, keyed by courses.colors.PALETTE.
glob COURSE_BLOCK: dict[str, str] = {
    "indigo": "border border-indigo-200 bg-indigo-50 text-indigo-900",
    "teal": "border border-teal-200 bg-teal-50 text-teal-900",
    "amber": "border border-amber-200 bg-amber-50 text-amber-900",
    "rose": "border border-rose-200 bg-rose-50 text-rose-900",
    "sky": "border border-sky-200 bg-sky-50 text-sky-900",
    "violet": "border border-violet-200 bg-violet-50 text-violet-900",
    "emerald": "border border-emerald-200 bg-emerald-50 text-emerald-900",
    "orange": "border border-orange-200 bg-orange-50 text-orange-900"
};

glob COURSE_ACCENT: dict[str, str] = {
    "indigo": "border-l-4 border-l-indigo-500",
    "teal": "border-l-4 border-l-teal-500",
    "amber": "border-l-4 border-l-amber-500",
    "rose": "border-l-4 border-l-rose-500",
    "sky": "border-l-4 border-l-sky-500",
    "violet": "border-l-4 border-l-violet-500",
    "emerald": "border-l-4 border-l-emerald-500",
    "orange": "border-l-4 border-l-orange-500"
};

glob COURSE_DOT: dict[str, str] = {
    "indigo": "inline-block h-2 w-2 flex-none rounded-full bg-indigo-500",
    "teal": "inline-block h-2 w-2 flex-none rounded-full bg-teal-500",
    "amber": "inline-block h-2 w-2 flex-none rounded-full bg-amber-500",
    "rose": "inline-block h-2 w-2 flex-none rounded-full bg-rose-500",
    "sky": "inline-block h-2 w-2 flex-none rounded-full bg-sky-500",
    "violet": "inline-block h-2 w-2 flex-none rounded-full bg-violet-500",
    "emerald": "inline-block h-2 w-2 flex-none rounded-full bg-emerald-500",
    "orange": "inline-block h-2 w-2 flex-none rounded-full bg-orange-500"
};

glob COURSE_SWATCH: dict[str, str] = {
    "indigo": "h-6 w-6 rounded-full bg-indigo-500",
    "teal": "h-6 w-6 rounded-full bg-teal-500",
    "amber": "h-6 w-6 rounded-full bg-amber-500",
    "rose": "h-6 w-6 rounded-full bg-rose-500",
    "sky": "h-6 w-6 rounded-full bg-sky-500",
    "violet": "h-6 w-6 rounded-full bg-violet-500",
    "emerald": "h-6 w-6 rounded-full bg-emerald-500",
    "orange": "h-6 w-6 rounded-full bg-orange-500"
};
