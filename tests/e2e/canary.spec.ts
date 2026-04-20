import { test, expect } from '@playwright/test';
import { injectAxe, checkA11y } from 'axe-playwright';

test.describe('canary', () => {
  test('root page loads and has no accessibility violations', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('h1')).toContainText('Agentic Harness');

    // Accessibility audit — axe-core AA level
    await injectAxe(page);
    await checkA11y(page, undefined, {
      axeOptions: {
        runOnly: {
          type: 'tag',
          values: ['wcag2a', 'wcag2aa'],
        },
      },
      detailedReport: true,
    });
  });
});
