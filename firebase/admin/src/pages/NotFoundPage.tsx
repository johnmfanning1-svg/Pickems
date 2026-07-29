import { Link } from "react-router-dom";
import { PageHeader } from "@/components/Card";

export function NotFoundPage() {
  return (
    <>
      <PageHeader title="Not found" subtitle="No admin screen lives at this path." />
      <Link to="/" className="text-sm text-slate-400 underline hover:text-slate-200">
        Back to dashboard
      </Link>
    </>
  );
}
