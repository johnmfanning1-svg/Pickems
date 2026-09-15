import { createBrowserRouter } from "react-router-dom";
import { RequireAdmin } from "@/auth/RequireAdmin";
import { AppLayout } from "@/components/AppLayout";
import { ADMIN_BASENAME } from "@/lib/adminBase";
import { AuditLogPage } from "@/pages/AuditLogPage";
import { AuditWeeksPage } from "@/pages/AuditWeeksPage";
import { ConfigPage } from "@/pages/ConfigPage";
import { DashboardPage } from "@/pages/DashboardPage";
import { GroupDetailPage } from "@/pages/GroupDetailPage";
import { GroupMembersPage } from "@/pages/GroupMembersPage";
import { GroupWeeksPage } from "@/pages/GroupWeeksPage";
import { GroupsPage } from "@/pages/GroupsPage";
import { LoginPage } from "@/pages/LoginPage";
import { ModerationPage } from "@/pages/ModerationPage";
import { NotFoundPage } from "@/pages/NotFoundPage";
import { SupportInboxPage } from "@/pages/SupportInboxPage";
import { WeekPicksPage } from "@/pages/WeekPicksPage";

/**
 * The SPA is served at `/admin/` (Vite `base` + Hosting rewrite). Public `/`
 * is the marketing homepage. `/join` and `/support` are static HTML rewritten
 * before `/admin/**` → `/admin/index.html`. `RequireAdmin` wraps everything
 * except /login.
 */
export const router = createBrowserRouter(
  [
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
            { path: "/groups/:id/weeks/:weekId/picks", element: <WeekPicksPage /> },
            { path: "/config", element: <ConfigPage /> },
            { path: "/support-inbox", element: <SupportInboxPage /> },
            { path: "/audit/weeks", element: <AuditWeeksPage /> },
            { path: "/audit/log", element: <AuditLogPage /> },
            { path: "/moderation", element: <ModerationPage /> },
            { path: "*", element: <NotFoundPage /> },
          ],
        },
      ],
    },
  ],
  { basename: ADMIN_BASENAME },
);
