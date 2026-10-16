"""Settings: the day's bounds, Deep Work cutoff, buffers, protected hours, and sign out."""

import from "@jac/runtime" { jacLogout, useNavigate }
import from .store {
    ProfileResult,
    ProfileView,
    ProtectedView,
    add_protected_hours,
    get_profile,
    remove_protected_hours,
    save_profile
}
import from ..shell.PlannerContext { usePlanner }
import from ..shared.errors { error_message }
import from ..shared.styles { BUTTON, BUTTON_PRIMARY, BUTTON_SMALL, CARD, CARD_STACK, COLUMNS, FIELD, HINT, LABEL }
import from ..shared.ui { CardHeader, Notice }

glob FIELD_GRID: str = "grid grid-cols-1 gap-4 desk:grid-cols-2";

def:pub ProtectedRow(block: ProtectedView, busy: bool, onRemove: Callable[[str], None]) -> JsxElement {
    def handle_remove(e: MouseEvent) {
        onRemove(block.id);
    }
    <li className="flex items-center gap-3 py-2.5 text-[12.5px]">
        <span className="font-semibold">{block.label}</span>
        <span className="tabular-nums text-muted">{f"{block.start} – {block.end}"}</span>
        <button type="button" className={BUTTON_SMALL + " ml-auto"} disabled={busy} onClick={handle_remove} aria-label={f"Remove {block.label}"}>Remove</button>
    </li>
}

def:pub SettingsPage -> JsxElement {
    ctx: any = usePlanner();
    nav = useNavigate();
    has profile: ProfileView | None = None;
    has display_name: str = "";
    has timezone: str = "";
    has day_start: str = "08:00";
    has day_end: str = "22:00";
    has cutoff: str = "21:00";
    has buffer: str = "10";
    has min_slot: str = "15";
    has block_label: str = "";
    has block_start: str = "17:00";
    has block_end: str = "19:00";
    has failure: str = "";
    has notice: str = "";
    has busy: bool = False;

    def fill(view: ProfileView);
    async def load -> None;
    async def applyResult(result: ProfileResult | None, success: str) -> None;
    async def saveProfile -> None;
    async def addBlock -> None;
    async def removeBlock(block_id: str) -> None;

    def signOut(e: MouseEvent) {
        jacLogout();
        nav("/login", {"replace": True});
    }

    async can with entry {
        await load();
    }

    <div className={COLUMNS}>
        <div className={CARD_STACK}>
            <Notice tone="error" message={failure} />
            <Notice tone="success" message={notice} />
            <section className={CARD} aria-labelledby="day-h">
                <CardHeader title="Your day" titleId="day-h" aside="The agent only plans inside these hours" />
                <form
                    className="flex flex-col gap-4 px-4 pt-3 pb-4"
                    onSubmit={lambda (e: FormEvent) { e.preventDefault(); saveProfile(); }}
                    noValidate={True}
                >
                    <div className={FIELD_GRID}>
                        <div>
                            <label className={LABEL} htmlFor="set-name">Name</label>
                            <input id="set-name" className={FIELD} value={display_name} onChange={lambda (e: ChangeEvent) { display_name = e.target.value; }} />
                        </div>
                        <div>
                            <label className={LABEL} htmlFor="set-tz">Time zone</label>
                            <input id="set-tz" className={FIELD} value={timezone} onChange={lambda (e: ChangeEvent) { timezone = e.target.value; }} aria-describedby="set-tz-hint" />
                            <p id="set-tz-hint" className={HINT}>An IANA name, e.g. America/Detroit.</p>
                        </div>
                        <div>
                            <label className={LABEL} htmlFor="set-start">Day starts</label>
                            <input id="set-start" type="time" className={FIELD} value={day_start} onChange={lambda (e: ChangeEvent) { day_start = e.target.value; }} />
                        </div>
                        <div>
                            <label className={LABEL} htmlFor="set-end">Day ends</label>
                            <input id="set-end" type="time" className={FIELD} value={day_end} onChange={lambda (e: ChangeEvent) { day_end = e.target.value; }} />
                        </div>
                        <div>
                            <label className={LABEL} htmlFor="set-cutoff">No Deep Work after</label>
                            <input id="set-cutoff" type="time" className={FIELD} value={cutoff} onChange={lambda (e: ChangeEvent) { cutoff = e.target.value; }} />
                        </div>
                        <div>
                            <label className={LABEL} htmlFor="set-buffer">Buffer around classes (minutes)</label>
                            <input id="set-buffer" type="number" min="0" max="60" className={FIELD} value={buffer} onChange={lambda (e: ChangeEvent) { buffer = e.target.value; }} />
                        </div>
                        <div>
                            <label className={LABEL} htmlFor="set-slot">Shortest useful slot (minutes)</label>
                            <input id="set-slot" type="number" min="5" max="120" className={FIELD} value={min_slot} onChange={lambda (e: ChangeEvent) { min_slot = e.target.value; }} />
                        </div>
                    </div>
                    <div><button type="submit" className={BUTTON_PRIMARY} disabled={busy}>Save settings</button></div>
                </form>
            </section>
        </div>
        <div className={CARD_STACK}>
            <section className={CARD} aria-labelledby="protected-h">
                <CardHeader title="Protected hours" titleId="protected-h" aside="Kept free every day" />
                <div className="px-4 pt-1 pb-4">
                    <ul className="m-0 list-none divide-y divide-line p-0">
                        {if profile is not None and len(profile.protected) == 0 {
                            <li className="py-2.5 text-[12.5px] text-muted">Nothing protected yet, e.g. dinner &amp; gym.</li>
                        }}
                        {if profile is not None {
                            for block in profile.protected {
                                <ProtectedRow key={block.id} block={block} busy={busy} onRemove={removeBlock} />
                            }
                        }}
                    </ul>
                    <form
                        className="mt-3 grid grid-cols-[1fr_auto_auto] items-end gap-2"
                        onSubmit={lambda (e: FormEvent) { e.preventDefault(); addBlock(); }}
                        noValidate={True}
                    >
                        <div className="col-span-3">
                            <label className={LABEL} htmlFor="block-label">Name</label>
                            <input id="block-label" className={FIELD} placeholder="Dinner & gym" value={block_label} onChange={lambda (e: ChangeEvent) { block_label = e.target.value; }} />
                        </div>
                        <div>
                            <label className={LABEL} htmlFor="block-start">From</label>
                            <input id="block-start" type="time" className={FIELD} value={block_start} onChange={lambda (e: ChangeEvent) { block_start = e.target.value; }} />
                        </div>
                        <div>
                            <label className={LABEL} htmlFor="block-end">To</label>
                            <input id="block-end" type="time" className={FIELD} value={block_end} onChange={lambda (e: ChangeEvent) { block_end = e.target.value; }} />
                        </div>
                        <button type="submit" className={BUTTON + " min-h-[42px]"} disabled={busy}>Add</button>
                    </form>
                </div>
            </section>
            <section className={CARD} aria-labelledby="account-h">
                <CardHeader title="Account" titleId="account-h" />
                <div className="px-4 pt-3 pb-4">
                    <button type="button" className={BUTTON} onClick={signOut}>Sign out</button>
                </div>
            </section>
        </div>
    </div>
}
