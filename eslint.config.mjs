import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import eslintConfigPrettier from 'eslint-config-prettier';
import jsxA11y from 'eslint-plugin-jsx-a11y';
import localRules from 'eslint-plugin-local-rules';

export default [
  // Global ignores
  {
    ignores: ['node_modules/', '.next/', 'dist/', 'coverage/', 'playwright-report/'],
  },

  // Base JS recommended
  js.configs.recommended,

  // TypeScript recommended
  ...tseslint.configs.recommended,

  // JSX a11y flat config
  jsxA11y.flatConfigs.recommended,

  // Prettier must be last to turn off conflicting rules
  eslintConfigPrettier,

  // TypeScript file settings
  {
    files: ['**/*.{ts,tsx}'],
    plugins: {
      'local-rules': localRules,
    },
    rules: {
      '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_' }],

      // Vendor seam enforcement
      'local-rules/no-vendor-outside-seam': [
        'error',
        {
          seams: [
            {
              packages: ['@clerk/nextjs', '@clerk/backend', '@clerk/types'],
              allowedIn: ['src/server/auth/'],
              seamImport: '@/server/auth',
            },
            {
              packages: ['posthog-js', 'posthog-node'],
              allowedIn: ['src/server/analytics/', 'src/server/flags/'],
              seamImport: '@/server/analytics or @/server/flags',
            },
            {
              packages: ['@sentry/nextjs', '@sentry/node', '@sentry/react'],
              allowedIn: ['src/server/observability/'],
              seamImport: '@/server/observability',
            },
            {
              packages: ['drizzle-orm', 'drizzle-kit'],
              allowedIn: ['src/server/db/', 'drizzle.config.ts'],
              seamImport: '@/server/db',
            },
          ],
        },
      ],
    },
  },

  // CJS files (custom ESLint rules, config files)
  {
    files: ['eslint-rules/**/*.js', 'eslint-local-rules.js', '*.config.cjs', '.eslintrc.cjs'],
    languageOptions: {
      sourceType: 'commonjs',
      globals: {
        module: 'readonly',
        require: 'readonly',
        __dirname: 'readonly',
        __filename: 'readonly',
      },
    },
    rules: {
      '@typescript-eslint/no-require-imports': 'off',
    },
  },

  // shadcn/ui components — disable a11y rules that are handled at usage site
  {
    files: ['src/components/ui/**/*.{ts,tsx}'],
    rules: {
      'jsx-a11y/label-has-associated-control': 'off',
    },
  },

  // Allow drizzle-kit in config files at project root
  {
    files: ['drizzle.config.*'],
    rules: {
      'local-rules/no-vendor-outside-seam': 'off',
    },
  },
];
