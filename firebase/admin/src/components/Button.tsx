import type { ButtonHTMLAttributes, ReactNode } from "react";
import { Spinner } from "./Spinner";

type Variant = "primary" | "secondary" | "danger" | "ghost";

const VARIANT_CLASSES: Record<Variant, string> = {
  primary: "bg-brand text-white hover:bg-brand-hover focus-visible:outline-brand",
  secondary: "bg-ink-600 text-slate-100 hover:bg-ink-700 focus-visible:outline-slate-400",
  danger: "bg-red-900 text-red-100 hover:bg-red-800 focus-visible:outline-red-500",
  ghost: "bg-transparent text-slate-300 hover:bg-ink-700 focus-visible:outline-slate-500",
};

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
  pending?: boolean;
  children: ReactNode;
}

export function Button({
  variant = "secondary",
  pending = false,
  disabled,
  className = "",
  children,
  ...rest
}: ButtonProps) {
  return (
    <button
      type="button"
      disabled={disabled || pending}
      className={`inline-flex items-center justify-center gap-2 rounded-md px-3 py-1.5 text-sm font-medium transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 disabled:cursor-not-allowed disabled:opacity-50 ${VARIANT_CLASSES[variant]} ${className}`}
      {...rest}
    >
      {pending ? <Spinner /> : null}
      {children}
    </button>
  );
}
