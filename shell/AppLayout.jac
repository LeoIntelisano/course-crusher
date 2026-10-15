"""The signed-in frame: sidebar or tab bar, top bar, and the current screen."""

import from "@jac/runtime" { Outlet, useLocation }
import from .nav { title_for }
import from .PlannerContext { PlannerProvider, usePlanner }
import from .Sidebar { Sidebar }
import from .TabBar { TabBar }
import from .TopBar { MobileContext, TopBar }
import from ..planner.views { TodayView }
import from ..shared.ui { Notice }

def:pub AppFrame -> JsxElement {
    ctx: any = usePlanner();
    location: any = useLocation();
    path: str = location.pathname;
    today: TodayView | None = ctx.today;
    ready = today is not None;

    def onEnergy(level: str) {
        ctx.changeEnergy(level);
    }

    can with [path] entry {
        document.title = f"{title_for(path)} · CourseCrusher";  # jac:ignore[W2001]
    }

    <div className="grid h-full overflow-hidden desk:grid-cols-[232px_minmax(0,1fr)]">
        <a
            href="#main"
            className="absolute -left-[9999px] top-0 z-[99] bg-ink px-3 py-2 text-white focus:left-2 focus:top-2"
        >
            Skip to main content
        </a>
        <Sidebar
            path={path}
            initials={today.initials if today else ""}
            name={today.display_name if today else ""}
            openTasks={today.open_tasks if today else 0}
            courseCount={today.course_count if today else 0}
        />
        <div className="flex min-w-0 flex-col overflow-hidden">
            <TopBar
                title={title_for(path)}
                dateLabel={today.date_label if today else ""}
                freeState={today.free_state if today else ""}
                freeUntil={today.free_until_label if today else ""}
                freeMinutes={today.free_minutes if today else 0}
                energy={today.energy if today else "High"}
                initials={today.initials if today else ""}
                ready={ready}
                onEnergy={onEnergy}
            />
            {ready and <MobileContext
                freeState={today.free_state}
                freeUntil={today.free_until_label}
                freeMinutes={today.free_minutes}
                energy={today.energy}
                onEnergy={onEnergy}
            />}
            <main id="main" className="flex-1 overflow-auto px-3.5 pt-3.5 pb-[84px] desk:px-[22px] desk:pt-4 desk:pb-[18px]">
                {ctx.failure and <div className="mb-3"><Notice tone="error" message={ctx.failure} /></div>}
                <Outlet />
            </main>
        </div>
        <TabBar path={path} />
    </div>
}

def:pub AppLayout -> JsxElement {
    <PlannerProvider><AppFrame /></PlannerProvider>
}
