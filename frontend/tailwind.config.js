/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{js,jsx}"],
  darkMode: "class",
  theme: {
    extend: {
      fontFamily: {
        sans: ["Inter", "ui-sans-serif", "system-ui"],
        varsity: ["Graduate", "serif"],
        chalk: ["Patrick Hand", "cursive"],
        crayon: ["ColoredCrayons", "Inter", "ui-sans-serif", "system-ui"],
      },
      colors: {
        charcoal: "#2A2A2A",
        burnt: "#D97745",
        olive: "#5C6F4E",
        warmgray: "#E6E3DE",
        surface: "#FFFFFF",
        border: "#D1CCC6",
        textPrimary: "#2A2A2A",
        textSecondary: "#6B6B6B",
        success: "#4C7A4F",
        warning: "#C2410C",
        info: "#8DA1B9",
        danger: "#991B1B",
        darkbg: "#1F1F1F",
        darksurface: "#2A2A2A",
        darkborder: "#3A3A3A",
      },
      boxShadow: {
        card: "0 10px 30px -12px rgba(42,42,42,0.25)",
      },
    },
  },
  plugins: [],
};
