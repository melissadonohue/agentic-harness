/**
 * ESLint rule: no-vendor-outside-seam
 *
 * Enforces vendor containment — vendor SDK imports are only allowed inside
 * their designated seam directories. This is the mechanical enforcement layer
 * for the charter's vendor seam architecture.
 *
 * Configuration is provided via rule options in .eslintrc.cjs. Each entry maps
 * a vendor package pattern to the seam directory where it is allowed.
 *
 * Error messages are remediation hints — they tell the agent what is wrong
 * and how to fix it.
 */

/** @type {import('eslint').Rule.RuleModule} */
module.exports = {
  meta: {
    type: 'problem',
    docs: {
      description: 'Disallow vendor SDK imports outside their designated seam directories',
      category: 'Architecture',
      recommended: true,
    },
    schema: [
      {
        type: 'object',
        properties: {
          seams: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                packages: {
                  type: 'array',
                  items: { type: 'string' },
                  description: 'Vendor package names (exact match or prefix with /)',
                },
                allowedIn: {
                  type: 'array',
                  items: { type: 'string' },
                  description:
                    'Directory prefixes where the import is allowed (relative to project root)',
                },
                seamImport: {
                  type: 'string',
                  description: 'The correct import path to suggest in error messages',
                },
              },
              required: ['packages', 'allowedIn', 'seamImport'],
              additionalProperties: false,
            },
          },
        },
        additionalProperties: false,
      },
    ],
    messages: {
      vendorOutsideSeam:
        "Import '{{ importSource }}' is only allowed inside '{{ allowedIn }}'. " +
        "Use the seam's exported interface instead: import { ... } from '{{ seamImport }}'.",
    },
  },

  create(context) {
    const options = context.options[0] || {};
    const seams = options.seams || [];

    /**
     * Normalize a file path to use forward slashes and be relative-ish.
     * We compare against directory prefixes like 'src/server/auth/'.
     */
    function getRelativeFilePath() {
      const filename = context.getFilename();
      // Normalize to forward slashes
      const normalized = filename.replace(/\\/g, '/');
      // Try to extract the path relative to the project root.
      // Look for common root markers: src/, tests/, eslint-rules/, etc.
      const srcIndex = normalized.lastIndexOf('/src/');
      if (srcIndex !== -1) {
        return normalized.slice(srcIndex + 1); // 'src/server/auth/index.ts'
      }
      return normalized;
    }

    /**
     * Check if a given import source matches any vendor package in a seam config.
     */
    function matchesPackage(importSource, packages) {
      return packages.some((pkg) => {
        return importSource === pkg || importSource.startsWith(pkg + '/');
      });
    }

    /**
     * Check if the current file is inside one of the allowed directories.
     */
    function isInsideAllowedDir(relativeFilePath, allowedDirs) {
      return allowedDirs.some((dir) => {
        return relativeFilePath.startsWith(dir);
      });
    }

    /**
     * Core check: given an import source string, report if it violates seam containment.
     */
    function checkImport(node, importSource) {
      if (!importSource || typeof importSource !== 'string') return;

      const relativeFilePath = getRelativeFilePath();

      for (const seam of seams) {
        if (matchesPackage(importSource, seam.packages)) {
          if (!isInsideAllowedDir(relativeFilePath, seam.allowedIn)) {
            context.report({
              node,
              messageId: 'vendorOutsideSeam',
              data: {
                importSource,
                allowedIn: seam.allowedIn.join("' or '"),
                seamImport: seam.seamImport,
              },
            });
          }
          return; // Only report once per import, even if it matches multiple seams
        }
      }
    }

    return {
      // ES module imports: import { x } from '@clerk/nextjs'
      ImportDeclaration(node) {
        checkImport(node, node.source.value);
      },

      // CommonJS require: const x = require('@clerk/nextjs')
      CallExpression(node) {
        if (
          node.callee.type === 'Identifier' &&
          node.callee.name === 'require' &&
          node.arguments.length > 0 &&
          node.arguments[0].type === 'Literal' &&
          typeof node.arguments[0].value === 'string'
        ) {
          checkImport(node, node.arguments[0].value);
        }
      },
    };
  },
};
