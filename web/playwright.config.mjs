import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e',
  timeout: 30000,
  expect: {
    timeout: 5000,
  },
  use: {
    baseURL: process.env.BASE_URL || `http://localhost:${process.env.PORT || 8080}`,
    trace: 'off',
  },
  reporter: process.env.CI ? [['dot']] : [['list']],
});
