import type { ReactNode } from "react";
import { EmptyState } from "./Card";
import { Spinner } from "./Spinner";

export interface Column<T> {
  key: string;
  header: ReactNode;
  render: (row: T) => ReactNode;
  className?: string;
}

/**
 * Plain semantic table. Admin volume never justifies a data-grid dependency,
 * and a real `<table>` keeps keyboard and screen-reader behaviour for free.
 */
export function DataTable<T>({
  columns,
  rows,
  rowKey,
  loading = false,
  empty = "Nothing here.",
}: {
  columns: Column<T>[];
  rows: T[];
  rowKey: (row: T) => string;
  loading?: boolean;
  empty?: ReactNode;
}) {
  if (loading && rows.length === 0) {
    return (
      <div className="flex items-center gap-2 px-1 py-6 text-sm text-slate-400">
        <Spinner /> Loading…
      </div>
    );
  }
  if (rows.length === 0) return <EmptyState>{empty}</EmptyState>;

  return (
    <div className="-mx-4 overflow-x-auto px-4">
      <table className="min-w-full border-separate border-spacing-0 text-sm">
        <thead>
          <tr>
            {columns.map((column) => (
              <th
                key={column.key}
                scope="col"
                className={`sticky top-0 z-10 border-b border-ink-600 bg-ink-800 px-3 py-2 text-left text-xs font-semibold uppercase tracking-wide text-slate-400 ${column.className ?? ""}`}
              >
                {column.header}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={rowKey(row)} className="hover:bg-ink-700/50">
              {columns.map((column) => (
                <td
                  key={column.key}
                  className={`border-b border-ink-700 px-3 py-2 align-middle text-slate-200 ${column.className ?? ""}`}
                >
                  {column.render(row)}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
