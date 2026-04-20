import type { Config } from 'tailwindcss';

/**
 * Tailwind CSS v4 configuration.
 *
 * With Tailwind v4, the primary configuration lives in CSS (src/app/globals.css)
 * using @theme directives. This file exists as a compat shim for tools that
 * reference it — notably shadcn/ui's components.json.
 *
 * Do NOT add theme extensions here. Use @theme in globals.css instead.
 */
const config: Config = {
  darkMode: 'class',
  content: ['./src/**/*.{ts,tsx}'],
  theme: {
    extend: {},
  },
  plugins: [],
};

export default config;
