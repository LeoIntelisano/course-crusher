"""The Breakdown screen's sections: the subtask list, "Where it fits" and "Agent checks"."""

import from .drafts { DraftRow }
import from ..planner.fit { CheckView, FitBlock, FitDay, FitPreview }
import from ..shared.format { tier_key }
import from ..shared.styles { BLOCK, CARD, FIELD_INLINE }
import from ..shared.ui { CardHeader, EmptyState, PlainChip, TierChip }

glob TIERS: list[str] = ["Deep Work", "Shallow Work", "Low Energy"];
glob BOX_ON: str = "mt-0.5 grid h-[17px] w-[17px] flex-none place-items-center rounded-[5px] border-[1.5px] border-ink bg-ink text-[10px] text-white cursor-pointer";
glob BOX_OFF: str = "mt-0.5 grid h-[17px] w-[17px] flex-none place-items-center rounded-[5px] border-[1.5px] border-line-strong bg-surface text-[10px] text-white cursor-pointer";

def:pub SubtaskRow(
    row: DraftRow,
    index: int,
    when: str,
    editing: bool,
    onToggle: Callable[[int], None],
    onTitle: Callable[[int, str], None],
    onTier: Callable[[int, str], None],
    onMinutes: Callable[[int, str], None]
) -> JsxElement {
    def handle_toggle(e: MouseEvent) {
        onToggle(index);
    }
    <div className="flex items-start gap-3 px-3.5 py-2.5 desk:px-4 desk:py-3" data-testid="subtask-row">
        <button
            type="button"
            role="checkbox"
            aria-checked={row.included}
            aria-label={f"Include {row.title}"}
            className={BOX_ON if row.included else BOX_OFF}
            onClick={handle_toggle}
        >
            {"✓" if row.included else ""}
        </button>
        <span className="min-w-0 flex-1">
            {if editing {
                <div className="flex flex-col gap-2">
                    <input
                        aria-label={f"Subtask {index + 1} title"}
                        className={FIELD_INLINE + " w-full"}
                        value={row.title}
                        onChange={lambda (e: ChangeEvent) { onTitle(index, e.target.value); }}
                    />
                    <div className="flex flex-wrap gap-2">
                        <select
                            aria-label={f"Subtask {index + 1} tier"}
                            className={FIELD_INLINE}
                            value={row.tier}
                            onChange={lambda (e: ChangeEvent) { onTier(index, e.target.value); }}
                        >
                            {for tier in TIERS { <option key={tier} value={tier}>{tier}</option> }}
                        </select>
                        <input
                            aria-label={f"Subtask {index + 1} minutes"}
                            type="number"
                            min="1"
                            max="480"
                            className={FIELD_INLINE + " w-[110px]"}
                            value={str(row.minutes)}
                            onChange={lambda (e: ChangeEvent) { onMinutes(index, e.target.value); }}
                        />
                    </div>
                </div>
            } else {
                <div className={"text-[13.5px] font-semibold tracking-[-0.1px] " + ("" if row.included else "text-faint line-through")}>{row.title}</div>
                <div className="mt-1.5 flex flex-wrap items-center gap-1.5">
                    <TierChip tier={row.tier} />
                    <PlainChip text={f"{row.minutes} min"} />
                    <span className="text-[11.5px] tabular-nums text-muted">{when}</span>
                </div>
            }}
        </span>
    </div>
}

def:pub FitCard(preview: FitPreview | None) -> JsxElement {
    days: list[FitDay] = preview.days if preview is not None else [];
    buffer = preview.buffer_label if preview is not None else "";
    <section className={CARD} aria-labelledby="fit">
        <CardHeader title="Where it fits" titleId="fit" aside={preview.range_label if preview else ""} />
        {if len(days) == 0 {
            <EmptyState title="Nothing placed yet" detail="Break down an assignment to see where its subtasks land." />
            skip;
        }}
        <div className="px-4 pt-3 pb-4">
            {for (index, day) in enumerate(days) {
                <div key={day.day_label} className="grid min-h-[34px] grid-cols-[44px_1fr] gap-2.5">
                    <span className="pt-[9px] text-right text-[11px] tabular-nums text-faint">{day.day_label}</span>
                    <span className="border-t border-line py-1">
                        <div className={BLOCK[tier_key(day.tier)] if day.tier else BLOCK["event"]}>
                            <div className="font-[650]">{day.title}</div>
                            <div className="mt-px text-[10.5px] opacity-90">
                                {day.detail}
                                {index == len(days) - 1 and buffer and f" — {buffer}"}
                            </div>
                        </div>
                    </span>
                </div>
            }}
        </div>
    </section>
}

def:pub CheckRow(check: CheckView) -> JsxElement {
    passed = check.level == "ok";
    <div className="flex items-center gap-2.5 py-[9px] text-[12.5px]">
        <span className="grid h-6 w-6 place-items-center rounded-md border border-line bg-canvas text-[11px] font-bold text-muted" aria-hidden="true">{"✓" if passed else "!"}</span>
        <span className="font-semibold">{check.message}</span>
        {not passed and <span className="ml-auto inline-flex items-center gap-[5px] text-[11.5px] text-danger"><i className="inline-block h-1.5 w-1.5 rounded-full bg-danger"></i>Review</span>}
    </div>
}

def:pub ChecksCard(preview: FitPreview | None) -> JsxElement {
    checks: list[CheckView] = preview.checks if preview is not None else [];
    <section className={CARD} aria-labelledby="chk">
        <CardHeader title="Agent checks" titleId="chk" />
        <div className="divide-y divide-line px-4 pt-1.5 pb-3.5">
            {if preview is None {
                <p className="m-0 py-2 text-[12.5px] text-muted">Checks run once there's a breakdown.</p>
                skip;
            }}
            {for check in checks {
                <CheckRow key={check.message} check={check} />
            }}
        </div>
    </section>
}

"""When each checked row would start, matched by position among the checked rows."""
def:pub when_labels(rows: list[DraftRow], preview: FitPreview | None) -> list[str] {
    labels: list[str] = [];
    blocks: list[FitBlock] = preview.blocks if preview else [];
    position = 0;
    for row in rows {
        if not row.included {
            labels = labels + ["Not added"];
            continue;
        }
        label = blocks[position].when_label if position < len(blocks) else "";
        labels = labels + [label];
        position = position + 1;
    }
    return labels;
}
