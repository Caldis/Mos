import type { Config } from "tailwindcss";

export default {
  content: [
    "./pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./components/**/*.{js,ts,jsx,tsx,mdx}",
    "./app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      opacity: {
        "3": "0.03",
        "7": "0.07",
        "8": "0.08",
        "9": "0.09",
        "12": "0.12",
        "14": "0.14",
        "28": "0.28",
        "62": "0.62",
        "66": "0.66",
        "68": "0.68",
        "72": "0.72",
        "82": "0.82",
        "92": "0.92",
      },
    },
  },
  plugins: [],
} satisfies Config;
