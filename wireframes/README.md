# CourseCrusher — UI wireframe

`index.html` is the wireframe. Open it in a browser; no build step, no dependencies.

```bash
open wireframes/index.html
```

It is a single responsive document, not two mockups. Resize the window past 900px
to cross the breakpoint — the sidebar becomes a bottom tab bar, the two-column
grid stacks, and task rows wrap instead of truncating.

## What it covers

| Screen | State |
|---|---|
| **Today** | The agent's pick, the follow-on queue, the week's load by tier, the auto-fitted day, connector status, and the CLI running the same query |
| **Breakdown** | One Canvas assignment split into subtasks, each with a tier, an estimate and a proposed slot, plus the clash checks the agent ran |
| Plan / Courses / Connections / Settings | Labelled stubs — out of scope for v1 |

Nav is live: click sidebar or tab-bar items to switch. `?screen=breakdown` deep-links
a screen, which is how the slide exports were captured.

## The three effort tiers

Tier drives everything the agent decides, so it is visible on every surface:

| Tier | Token | Example |
|---|---|---|
| Deep Work | `--deep` `#4338CA` | implementing gradient descent |
| Shallow Work | `--shallow` `#0F766E` | emailing a professor |
| Low Energy | `--low` `#A16207` | assigned reading |

Colour is never the only signal — every tier dot or chip is paired with its label.

## Conventions worth keeping when this becomes real UI

- Tokens live in `:root`. Nothing hardcodes a hex outside that block except the
  per-bar widths in the weekly-load card.
- The agent never schedules silently: the recommendation card states *why now*, and
  the breakdown screen says "nothing is scheduled until you confirm".
- Accessibility is built in, not retrofitted: skip link, `:focus-visible` rings,
  `aria-current` on nav, `aria-labelledby` on every card, 44px+ touch targets on
  mobile, and semantic `<header>` / `<nav>` / `<main>`.
- Grid children carry `min-width:0`. Without it the nowrap task titles widen the
  whole column instead of ellipsing, and the mobile layout overflows horizontally.

## Exports

`desktop-1440.png` (1440×810 @2x) and `mobile-390.png` (two 390×844 screens @2x)
are the renders embedded in slide 4 of the deck. Regenerate them with headless Chrome:

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars --force-device-scale-factor=2 --window-size=1440,810 --screenshot=wireframes/desktop-1440.png "file://$PWD/wireframes/index.html"
```

Note: Chrome clamps `--window-size` to a minimum window width, so a direct 390px
screenshot renders at the wrong viewport. The mobile export was captured by loading
the page in a 390px-wide `<iframe>` inside a full-size harness page instead.
