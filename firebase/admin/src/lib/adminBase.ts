/** Hosting path for the admin SPA. Keep in sync with Vite `base`. */
export const ADMIN_BASENAME = "/admin";

/**
 * `location.pathname` may include `/admin` (browser URL) or already be
 * basename-stripped (React Router). Normalize to an in-app route path.
 */
export function toRouterPath(pathname: string): string {
  if (pathname === ADMIN_BASENAME || pathname === `${ADMIN_BASENAME}/`) return "/";
  if (pathname.startsWith(`${ADMIN_BASENAME}/`)) {
    const rest = pathname.slice(ADMIN_BASENAME.length);
    return rest.startsWith("/") ? rest : `/${rest}`;
  }
  return pathname.startsWith("/") ? pathname : `/${pathname}`;
}
