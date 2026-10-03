// Captures the step-5 walkthrough screenshots for profile/README.md. See README.md for the required local stack.
const { chromium } = require('playwright-core');
const out = require('path').join(__dirname, '..', '..', 'profile', 'images') + '/';
const clean = async page => { await page.addStyleTag({ content: '#__vue-devtools-container__, #vue-inspector-container { display: none !important; }' }); await page.waitForTimeout(300); };
const shot = async (page, name, opts = {}) => { await clean(page); if (opts.dialog) { await page.locator('.v-overlay--active .v-overlay__content').last().screenshot({ path: out + name }); } else { await page.screenshot({ path: out + name, ...opts }); } console.log('saved', name); };
(async () => {
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  const page = await browser.newPage({ viewport: { width: 1400, height: 720 } });
  await page.goto('http://localhost:5173/nodes');
  await page.getByText('System nodes').waitFor({ timeout: 20000 });
  await page.waitForTimeout(1500);
  await page.locator('.v-app-bar-nav-icon').click(); await page.waitForTimeout(800);
  await shot(page, 'configure-nodes-empty.png');
  await page.locator('.v-app-bar-nav-icon').click(); await page.waitForTimeout(500);

  await page.getByRole('button', { name: /new node/i }).click();
  await page.getByLabel('Node Name').fill('Garage node');
  await page.getByLabel('Node Id').click(); await page.waitForTimeout(600);
  await page.locator('.v-overlay--active .v-overlay__content').first().screenshot({ path: out + 'node-new.png' }); console.log('saved node-new.png');
  await page.locator('.v-list-item').filter({ hasText: '5A1E7C3B' }).first().click();

  await page.getByRole('button', { name: /new device/i }).click(); await page.waitForTimeout(1200);
  await shot(page, 'device-templates.png');
  await page.getByRole('row').filter({ hasText: 'RIoT2.Net.Devices.Catalog.Web' }).locator('input[type=checkbox]').check();
  await page.getByRole('button', { name: /^add/i }).last().click(); await page.waitForTimeout(1000);
  await page.getByRole('button', { name: /Web \[new\]/ }).click(); await page.waitForTimeout(800);
  await page.getByLabel('Device Name').fill('Webhooks');

  await page.getByRole('button', { name: /new report template/i }).click(); await page.waitForTimeout(800);
  const dlg = page.locator('.v-overlay--active').last();
  await dlg.getByLabel('Name').fill('Webhook value');
  await dlg.getByLabel('Address').fill('test');
  await dlg.locator('.v-select').filter({ hasText: 'Type' }).first().click(); await page.waitForTimeout(400);
  await page.locator('.v-overlay--active .v-list-item').filter({ hasText: /^Number$/ }).first().click();
  await page.waitForTimeout(500);
  await shot(page, 'report-template.png', { dialog: true });
  await dlg.getByRole('button', { name: /save/i }).click(); await page.waitForTimeout(800);
  await page.getByRole('button', { name: /^save/i }).last().click(); await page.waitForTimeout(6000);
  await page.goto('http://localhost:5173/nodes'); await page.getByText('System nodes').waitFor(); await page.waitForTimeout(4000);
  await shot(page, 'configure-nodes.png', { clip: { x: 0, y: 64, width: 1400, height: 260 } });

  await page.goto('http://localhost:5173/variables'); await page.waitForTimeout(4000);
  await page.getByRole('button', { name: /add new/i }).click(); await page.waitForTimeout(800);
  const v = page.locator('.v-overlay--active').last();
  await v.getByLabel('Name').fill('WebHook');
  await v.getByLabel('Description').fill('Last value received from the webhook');
  await v.locator('.v-select').filter({ hasText: 'Type' }).first().click(); await page.waitForTimeout(400);
  await page.locator('.v-overlay--active .v-list-item').filter({ hasText: /^Number$/ }).first().click();
  await page.waitForTimeout(500);
  await shot(page, 'variable.png', { dialog: true });
  await browser.close();
})().catch(e => { console.error(e); process.exit(1); });


