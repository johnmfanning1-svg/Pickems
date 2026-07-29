import { Navigate, Outlet, useLocation } from "react-router-dom";
import { FullPageSpinner } from "@/components/Spinner";
import { useAuth } from "./AuthContext";

/** Route guard for everything except `/login`. */
export function RequireAdmin() {
  const { status } = useAuth();
  const location = useLocation();

  if (status === "loading") return <FullPageSpinner label="Checking admin claim…" />;
  if (status !== "admin") {
    return <Navigate to="/login" replace state={{ from: location.pathname }} />;
  }
  return <Outlet />;
}
