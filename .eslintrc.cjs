/** @type {import('eslint').Linter.Config} */
module.exports = {
  root: true,
  env: {
    browser: true,
    es2022: true,
    node: true,
  },
  extends: ['eslint:recommended', 'prettier'],
  parserOptions: {
    ecmaVersion: 'latest',
    sourceType: 'module',
    ecmaFeatures: {
      jsx: true,
    },
  },
  plugins: ['jsx-a11y', 'local-rules'],
  ignorePatterns: ['.next/', 'node_modules/', 'dist/', 'coverage/', 'playwright-report/'],
  rules: {
    // Vendor seam containment — the harness's most important architectural invariant.
    // Each entry maps vendor packages to the seam directory where they are allowed.
    // See eslint-rules/CLAUDE.md for the full seam mapping table.
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
  overrides: [
    // TypeScript files
    {
      files: ['*.ts', '*.tsx'],
      parser: '@typescript-eslint/parser',
      parserOptions: {
        ecmaVersion: 'latest',
        sourceType: 'module',
        ecmaFeatures: { jsx: true },
      },
      plugins: ['@typescript-eslint', 'react', 'react-hooks'],
      extends: [
        'plugin:@typescript-eslint/recommended',
        'plugin:react/recommended',
        'plugin:react-hooks/recommended',
        'prettier',
      ],
      settings: {
        react: { version: 'detect' },
      },
      rules: {
        'react/react-in-jsx-scope': 'off',
        'react/prop-types': 'off',
        '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
      },
    },
    // Custom ESLint rules and config files are CJS modules
    {
      files: [
        'eslint-rules/**/*.js',
        'eslint-local-rules.js',
        '*.config.cjs',
        '.eslintrc.cjs',
        'commitlint.config.cjs',
      ],
      env: {
        node: true,
        browser: false,
      },
    },
  ],
};
