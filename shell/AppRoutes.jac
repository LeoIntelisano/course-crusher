"""Every route. Sign-in and sign-up are public; everything else needs a session."""

import from "@jac/runtime" { AuthGuard, Navigate, Route, Router, Routes }
import from .AppLayout { AppLayout }
import from ..account.LoginPage { LoginPage }
import from ..account.SettingsPage { SettingsPage }
import from ..account.SignupPage { SignupPage }
import from ..connections.ConnectionsPage { ConnectionsPage }
import from ..connections.GoogleCallbackPage { GoogleCallbackPage }
import from ..courses.BreakdownPage { BreakdownPage }
import from ..courses.CoursesPage { CoursesPage }
import from ..planner.PlanPage { PlanPage }
import from ..planner.TodayPage { TodayPage }

def:pub AppRoutes -> JsxElement {
    <Router>
        <Routes>
            <Route path="/login" element={<LoginPage />} />
            <Route path="/signup" element={<SignupPage />} />
            <Route element={<AuthGuard redirect="/login" />}>
                <Route element={<AppLayout />}>
                    <Route path="/" element={<TodayPage />} />
                    <Route path="/plan" element={<PlanPage />} />
                    <Route path="/breakdown" element={<BreakdownPage />} />
                    <Route path="/courses" element={<CoursesPage />} />
                    <Route path="/connections" element={<ConnectionsPage />} />
                    <Route path="/connections/google/callback" element={<GoogleCallbackPage />} />
                    <Route path="/settings" element={<SettingsPage />} />
                    <Route path="*" element={<Navigate to="/" replace={True} />} />
                </Route>
            </Route>
        </Routes>
    </Router>
}
