import { NavLink, Outlet } from "react-router-dom";
import { useAuth } from "@/auth/AuthContext";
import { environmentLabel, useEmulators } from "@/lib/firebase";
import { Button } from "./Button";

const NAV_ITEMS: { to: string; label: string; end?: boolean }[] = [
  { to: "/", label: "Dashboard", end: true },
  { to: "/groups", label: "Groups" },
  { to: "/config", label: "App config" },
  { to: "/moderation", label: "Moderation" },
  { to: "/audit/weeks", label: "Week audit" },
  { to: "/audit/log", label: "Audit log" },
];

export function AppLayout() {
  const { user, signOutNow } = useAuth();

  return (
    <div className="flex min-h-screen flex-col">
      <header className="border-b border-ink-600 bg-ink-800">
        <div className="mx-auto flex max-w-7xl flex-wrap items-center gap-x-4 gap-y-2 px-4 py-3">
          <div className="flex items-center gap-2">
            <span className="text-sm font-bold uppercase tracking-widest text-brand">Pickems</span>
            <span className="text-sm text-slate-400">Admin</span>
          </div>
          <span
            className={`rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${
              useEmulators
                ? "bg-sky-950 text-sky-300 ring-sky-800"
                : "bg-red-950 text-red-300 ring-red-800"
            }`}
          >
            {environmentLabel}
          </span>
          <div className="ml-auto flex items-center gap-3">
            <span className="hidden text-xs text-slate-400 sm:inline">{user?.email}</span>
            <Button variant="ghost" onClick={() => void signOutNow()}>
              Sign out
            </Button>
          </div>
        </div>
        <nav className="mx-auto flex max-w-7xl gap-1 overflow-x-auto px-2 pb-2">
          {NAV_ITEMS.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              end={item.end}
              className={({ isActive }) =>
                `whitespace-nowrap rounded-md px-3 py-1.5 text-sm transition-colors ${
                  isActive
                    ? "bg-ink-600 font-medium text-slate-50"
                    : "text-slate-400 hover:bg-ink-700 hover:text-slate-200"
                }`
              }
            >
              {item.label}
            </NavLink>
          ))}
        </nav>
      </header>

      <main className="mx-auto w-full max-w-7xl flex-1 space-y-6 px-4 py-6">
        <Outlet />
      </main>

      <footer className="border-t border-ink-600 px-4 py-3 text-center text-xs text-slate-600">
        Firestore rules are the security boundary — this console only makes privileged actions
        convenient. Every mutation is recorded in <code className="font-mono">adminAudit</code>.
      </footer>
    </div>
  );
}
