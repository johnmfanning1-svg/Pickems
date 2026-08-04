import type { ReactNode } from "react";

export function Card({
  title,
  description,
  actions,
  children,
  className = "",
}: {
  title?: string;
  description?: string;
  actions?: ReactNode;
  children?: ReactNode;
  className?: string;
}) {
  return (
    <section className={`rounded-xl border border-ink-600 bg-ink-800 ${className}`}>
      {title || actions ? (
        <header className="flex flex-wrap items-start justify-between gap-3 border-b border-ink-600 px-4 py-3">
          <div className="min-w-0">
            {title ? <h2 className="text-sm font-semibold text-slate-100">{title}</h2> : null}
            {description ? <p className="mt-0.5 text-xs text-slate-400">{description}</p> : null}
          </div>
          {actions ? <div className="flex shrink-0 items-center gap-2">{actions}</div> : null}
        </header>
      ) : null}
      <div className="p-4">{children}</div>
    </section>
  );
}

export function PageHeader({
  title,
  subtitle,
  actions,
}: {
  title: string;
  subtitle?: ReactNode;
  actions?: ReactNode;
}) {
  return (
    <header className="flex flex-wrap items-end justify-between gap-3">
      <div className="min-w-0">
        <h1 className="truncate text-xl font-semibold text-slate-50">{title}</h1>
        {subtitle ? <div className="mt-1 text-sm text-slate-400">{subtitle}</div> : null}
      </div>
      {actions ? <div className="flex flex-wrap items-center gap-2">{actions}</div> : null}
    </header>
  );
}

export function StatTile({
  label,
  value,
  hint,
}: {
  label: string;
  value: ReactNode;
  hint?: string;
}) {
  return (
    <div className="rounded-xl border border-ink-600 bg-ink-800 px-4 py-3">
      <p className="text-xs uppercase tracking-wide text-slate-500">{label}</p>
      <p className="mt-1 text-2xl font-semibold text-slate-50">{value}</p>
      {hint ? <p className="mt-0.5 text-xs text-slate-500">{hint}</p> : null}
    </div>
  );
}

export function EmptyState({ children }: { children: ReactNode }) {
  return (
    <p className="rounded-lg border border-dashed border-ink-600 px-4 py-8 text-center text-sm text-slate-500">
      {children}
    </p>
  );
}
