import { createBrowserRouter } from "react-router-dom";
import { RequireAdmin } from "@/auth/RequireAdmin";
import { AppLayout } from "@/components/AppLayout";
import { AuditLogPage } from "@/pages/AuditLogPage";
import { AuditWeeksPage } from "@/pages/AuditWeeksPage";
import { ConfigPage } from "@/pages/ConfigPage";
import { DashboardPage } from "@/pages/DashboardPage";
import { GroupDetailPage } from "@/pages/GroupDetailPage";
import { GroupMembersPage } from "@/pages/GroupMembersPage";
import { GroupSeasonsPage } from "@/pages/GroupSeasonsPage";
import { GroupWeeksPage } from "@/pages/GroupWeeksPage";
import { GroupsPage } from "@/pages/GroupsPage";
import { LoginPage } from "@/pages/LoginPage";
import { ModerationPage } from "@/pages/ModerationPage";
import { NotFoundPage } from "@/pages/NotFoundPage";
import { WeekPicksPage } from "@/pages/WeekPicksPage";

/**
 * Hosting rewrites every path to /index.html, so browser history routing works
 * without hash URLs. `RequireAdmin` wraps everything except /login.
 */
export const router = createBrowserRouter([
  { path: "/login", element: <LoginPage /> },
  {
    element: <RequireAdmin />,
    children: [
      {
        element: <AppLayout />,
        children: [
          { path: "/", element: <DashboardPage /> },
          { path: "/groups", element: <GroupsPage /> },
          { path: "/groups/:id", element: <GroupDetailPage /> },
          { path: "/groups/:id/members", element: <GroupMembersPage /> },
          { path: "/groups/:id/weeks", element: <GroupWeeksPage /> },
          { path: "/groups/:id/seasons", element: <GroupSeasonsPage /> },
          { path: "/groups/:id/weeks/:weekId/picks", element: <WeekPicksPage /> },
          { path: "/config", element: <ConfigPage /> },
          { path: "/audit/weeks", element: <AuditWeeksPage /> },
          { path: "/audit/log", element: <AuditLogPage /> },
          { path: "/moderation", element: <ModerationPage /> },
          { path: "*", element: <NotFoundPage /> },
        ],
      },
    ],
  },
]);
