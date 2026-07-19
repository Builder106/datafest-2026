import { createBdd } from 'playwright-bdd';
import { expect } from '@playwright/test';

const { Given, Then } = createBdd();

Given('I am on the research site', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('.stats-wrap')).toBeVisible({ timeout: 10_000 });
});

Then('the page title contains {string}', async ({ page }, text: string) => {
  await expect(page).toHaveTitle(new RegExp(text));
});

Then('the adjusted odds ratio {string} is visible', async ({ page }, value: string) => {
  await expect(page.locator('.stat-num').first()).toContainText(value);
});

Then('the ED rate {string} is visible', async ({ page }, value: string) => {
  await expect(page.locator('.stat-num').nth(1)).toContainText(value);
});

Then('the journey SVG is visible', async ({ page }) => {
  await expect(page.locator('svg.journey-svg')).toBeVisible();
});

Then('the transport barrier bar chart is visible', async ({ page }) => {
  await expect(page.locator('.bars')).toBeVisible();
  await expect(page.locator('.bar-row')).toHaveCount(2);
});

Then('all {int} robustness check cards are present', async ({ page }, count: number) => {
  await expect(page.locator('.check-grid .check')).toHaveCount(count);
});

Then('the judges writeup link is present', async ({ page }) => {
  await expect(page.locator('.deliverables a').filter({ hasText: /writeup/i })).toBeVisible();
});

Then('the presentation deck link is present', async ({ page }) => {
  await expect(page.locator('.deliverables a').filter({ hasText: /presentation/i })).toBeVisible();
});
