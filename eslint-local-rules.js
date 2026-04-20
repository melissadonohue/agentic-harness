/**
 * Entry point for eslint-plugin-local-rules.
 * Re-exports custom rules from the eslint-rules/ directory.
 *
 * Usage in .eslintrc.cjs: 'local-rules/no-vendor-outside-seam'
 */
module.exports = {
  'no-vendor-outside-seam': require('./eslint-rules/no-vendor-outside-seam'),
};
