"""Today's plan, shared by the top bar, the sidebar and every screen that changes it.

Screens call `refreshToday()` after a write so the header pills, counts and the
Today screen stay in step without each fetching on its own.
"""

import from "react" { createContext, useContext }
import from "@jac/runtime" { jacLogout, useNavigate }
import from ..account.store { ProfileResult, set_energy }
import from ..planner.service { get_today }
import from ..planner.views { TodayView }
import from ..shared.errors { error_message, is_unauthorized }
import from .status { energy_notice }

glob PlannerCtx = createContext(None);

def:pub PlannerProvider(children: any = None) -> JsxElement {
    has today: TodayView | None = None;
    has loading: bool = True;
    has failure: str = "";
    has energyNotice: str = "";
    nav = useNavigate();

    """Task ids on today's plan from now on: Up next and the rest of today's queue."""
    def plannedIds(view: TodayView | None) -> list[str] {
        if view is None or view.up_next is None {
            return [];
        }
        return [view.up_next.item.task_id] + [item.task_id for item in view.queue];
    }

    async def refreshToday -> TodayView | None {
        latest: TodayView | None = None;
        try {
            latest = await get_today();
        } except Exception as err {
            if is_unauthorized(err) {
                jacLogout();
                nav("/login", {"replace": True});
                return None;
            }
            failure = error_message(err);
            loading = False;
            return None;
        }
        today = latest;
        failure = "";
        loading = False;
        return latest;
    }

    async def changeEnergy(level: str) -> None {
        before = plannedIds(today);
        energyNotice = "";
        result: ProfileResult | None = None;
        try {
            result = await set_energy(level);
        } except Exception as err {
            failure = error_message(err);
            return;
        }
        if result and not result.ok {
            failure = result.error;
            return;
        }
        latest = await refreshToday();
        if latest is not None {
            energyNotice = energy_notice(level, before, plannedIds(latest));
        }
    }

    async can with entry {
        await refreshToday();
    }

    # Context values cross React's untyped boundary, hence the plain dict.
    value = {
        "today": today,
        "loading": loading,
        "failure": failure,
        "refreshToday": refreshToday,
        "changeEnergy": changeEnergy,
        "energyNotice": energyNotice,
        "dismissEnergyNotice": lambda { energyNotice = ""; }
    };
    <PlannerCtx.Provider value={value}>{children}</PlannerCtx.Provider>
}

# useContext returns whatever the provider stored: the dict built above.
def:pub usePlanner -> any {
    return useContext(PlannerCtx);
}
