import { NavLink } from "react-router-dom";

export function GroupTabs({ groupId }: { groupId: string }) {
  const items = [
    { to: `/groups/${groupId}`, label: "Overview", end: true },
    { to: `/groups/${groupId}/members`, label: "Members" },
    { to: `/groups/${groupId}/weeks`, label: "Weeks" },
    { to: `/groups/${groupId}/seasons`, label: "Seasons" },
  ];
  return (
    <nav className="flex gap-1 border-b border-ink-600 pb-2">
      {items.map((item) => (
        <NavLink
          key={item.to}
          to={item.to}
          end={item.end}
          className={({ isActive }) =>
            `rounded-md px-3 py-1 text-sm ${
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
  );
}
