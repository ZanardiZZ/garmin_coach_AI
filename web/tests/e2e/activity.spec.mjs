import { test, expect } from '@playwright/test';

const screenshotDir = process.env.SCREENSHOT_DIR || 'tests/e2e_ui/screenshots';

test('activity detail renders map and charts without console errors', async ({ page }) => {
  const errors = [];
  page.on('pageerror', (err) => errors.push(err));
  page.on('console', (msg) => {
    if (msg.type() === 'error') {
      errors.push(new Error(msg.text()));
    }
  });

  await page.goto('/activity/mock-001?athlete=zz', { waitUntil: 'networkidle' });
  await expect(page.locator('#map')).toBeVisible();
  await expect(page.locator('#map')).toHaveClass(/leaflet-container/);
  await expect(page.locator('#chart-hr.chart-clickable')).toBeVisible();
  await expect(page.locator('#chart-speed.chart-clickable')).toBeVisible();
  await expect(page.locator('#chart-alt.chart-clickable')).toBeVisible();

  expect(errors, `Console errors: ${errors.map((e) => e.message).join('; ')}`).toHaveLength(0);
});

test('capture UI screenshots with mock data', async ({ page }) => {
  const enableGrafana = process.env.GRAFANA_SMOKE === '1';
  const shots = [
    { name: 'dashboard', url: '/?athlete=zz' },
    { name: 'activities', url: '/activities?athlete=zz' },
    { name: 'activity-detail', url: '/activity/mock-001?athlete=zz' },
    { name: 'coach', url: '/coach?athlete=zz' },
    { name: 'setup', url: '/setup' },
  ];
  if (enableGrafana) {
    shots.push({ name: 'grafana', url: '/grafana' });
  }

  for (const shot of shots) {
    await page.goto(shot.url, { waitUntil: 'networkidle' });
    if (shot.name === 'activity-detail') {
      await expect(page.locator('#map')).toBeVisible();
      await expect(page.locator('#map')).toHaveClass(/leaflet-container/);
    }
    if (shot.name === 'grafana') {
      await expect(page.locator('iframe')).toBeVisible();
    }
    await page.setViewportSize({ width: 1400, height: 900 });
    await page.screenshot({
      path: `${screenshotDir}/${shot.name}.png`,
      fullPage: true,
    });
  }
});
