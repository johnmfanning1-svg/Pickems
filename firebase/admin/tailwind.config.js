/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        // Mirrors PickemsColors so the console reads as the same product.
        brand: {
          DEFAULT: "#DC2626",
          hover: "#B91C1C",
        },
        ink: {
          900: "#0B0F14",
          800: "#111827",
          700: "#1A2230",
          600: "#26303F",
        },
      },
      fontFamily: {
        sans: ["ui-sans-serif", "system-ui", "-apple-system", "Segoe UI", "Helvetica", "Arial", "sans-serif"],
        mono: ["ui-monospace", "SFMono-Regular", "Menlo", "monospace"],
      },
    },
  },
  plugins: [],
};
