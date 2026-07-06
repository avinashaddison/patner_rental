import type { Config } from 'tailwindcss';

const config: Config = {
  content: [
    './src/app/**/*.{ts,tsx}',
    './src/components/**/*.{ts,tsx}',
    './src/lib/**/*.{ts,tsx}',
  ],
  theme: {
    extend: {
      colors: {
        // Brand = hot pink/red. Reused across the whole console, so this drives
        // the accent everywhere.
        brand: {
          50: '#fff1f4',
          100: '#ffe1e9',
          200: '#ffc4d6',
          300: '#ff97b5',
          400: '#ff5d8a',
          500: '#fb2c63',
          600: '#e60a4d',
          700: '#c00842',
          800: '#9c0a3a',
          900: '#820c35',
        },
        // Brutalist secondary accents — flat and loud.
        acid: '#ffe600', // electric yellow
        ink: '#0a0a0a', // near-black for borders/shadows/text
      },
      borderRadius: {
        // Brutalism stays blocky — cap everything small.
        lg: '0.4rem',
        xl: '0.45rem',
        '2xl': '0.5rem',
        '3xl': '0.6rem',
        '4xl': '0.7rem',
      },
      boxShadow: {
        // Hard offset drop shadows — no blur, solid black. The brutalist signature.
        'brutal-xs': '2px 2px 0 0 #0a0a0a',
        'brutal-sm': '3px 3px 0 0 #0a0a0a',
        brutal: '4px 4px 0 0 #0a0a0a',
        'brutal-md': '6px 6px 0 0 #0a0a0a',
        'brutal-lg': '8px 8px 0 0 #0a0a0a',
        'brutal-xl': '12px 12px 0 0 #0a0a0a',
      },
      fontFamily: {
        sans: ['var(--font-inter)', 'system-ui', 'sans-serif'],
        mono: ['ui-monospace', 'SFMono-Regular', 'Menlo', 'monospace'],
      },
      keyframes: {
        'fade-in': {
          '0%': { opacity: '0', transform: 'translateY(4px)' },
          '100%': { opacity: '1', transform: 'translateY(0)' },
        },
        'pop-in': {
          '0%': { opacity: '0', transform: 'translate(-4px, -4px)' },
          '100%': { opacity: '1', transform: 'translate(0, 0)' },
        },
      },
      animation: {
        'fade-in': 'fade-in 0.18s ease-out',
        'pop-in': 'pop-in 0.14s steps(3, end)',
      },
    },
  },
  plugins: [],
};

export default config;
