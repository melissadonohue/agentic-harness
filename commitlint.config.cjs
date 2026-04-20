/** @type {import('@commitlint/types').UserConfig} */
module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    // Enforce conventional commit types used by the harness
    'type-enum': [
      2,
      'always',
      [
        'feat', // New feature
        'fix', // Bug fix
        'chore', // Maintenance, dependencies
        'docs', // Documentation
        'style', // Formatting, whitespace
        'refactor', // Code restructuring without behavior change
        'test', // Adding or updating tests
        'ci', // CI/CD configuration
        'perf', // Performance improvement
        'build', // Build system changes
        'revert', // Revert a previous commit
      ],
    ],
    // Subject line should be concise
    'subject-max-length': [2, 'always', 100],
  },
};
