const assert = require('node:assert/strict');
const {createHash} = require('node:crypto');
const {chromium} = require('playwright');

const origin = process.argv[2];
const email = 'browser-fixture@example.test';
const password = 'test password on localhost only';
const code = 'student-life-fixture';
const taskTitle = 'Browser and native share this task';

function sampleSnapshot() {
  const campus = Object.fromEntries(
    ['semesters', 'courses', 'assignments', 'exams', 'events', 'categories', 'records', 'budgets']
      .map(table => [table, []]),
  );
  const inner = JSON.stringify({
    createdAt: new Date().toISOString(),
    campus: JSON.stringify({schemaVersion: 3, entityType: 'CampusData', scoreScaleMax: 5, ...campus}),
    tasks: JSON.stringify({schemaVersion: 1, entityType: 'Task', records: [{
      id: 'test-task', title: taskTitle, estimatedMinutes: 25, isCompleted: false,
      dueAt: null, scheduledRange: null, priority: 'normal', steps: [], note: null,
    }]}),
  });
  return JSON.stringify({format: 'student-life-backup', version: 1, payload: inner,
    sha256: createHash('sha256').update(inner).digest('hex')});
}

async function browserAdapter(context) {
  const page = await context.newPage();
  await page.goto(`${origin}/storage-fixture`);
  const result = await page.evaluate(async ({email, password, code, snapshot}) => {
    const call = window.studentLifeFile;
    const base = '/student-life/cloud-accounts';
    const active = `${base}/test-account`;
    const retired = `${active}.signed-out`;
    const status = await window.studentLifeStart();
    if (status !== 'ready') throw new Error(status);
    await call('mkdir', '/student-life', null, null);
    await call('mkdir', base, null, null);
    await call('mkdir', active, null, null);
    const saved = new TextEncoder().encode('fixture');
    await call('write', `${active}/tasks.json.tmp`, null, saved);
    await call('rename', `${active}/tasks.json.tmp`, `${active}/tasks.json`, null);
    await call('rename', active, retired, null);
    const preserved = new TextDecoder().decode(await call('read', `${retired}/tasks.json`, null, null));
    await call('delete', retired, null, null);
    const left = await call('list', base, null, null);
    const request = window.studentLifeRequest;
    const json = {'Content-Type': 'application/json'};
    const credentials = new TextEncoder().encode(JSON.stringify({email, password, code}));
    const create = await request('POST', '/v1/register', JSON.stringify(json), credentials, 4096);
    const first = JSON.parse(new TextDecoder().decode(create.bytes));
    const upload = await request('PUT', '/v1/snapshot', JSON.stringify({
      Authorization: `Bearer ${first.token}`, 'If-Match': '"0"', 'X-Upload-Id': 'a'.repeat(32),
    }), new TextEncoder().encode(snapshot), 0);
    const logout = await request('DELETE', '/v1/session', JSON.stringify({Authorization: `Bearer ${first.token}`}), null, 0);
    const login = await request('POST', '/v1/login', JSON.stringify(json), credentials, 4096);
    const second = JSON.parse(new TextDecoder().decode(login.bytes));
    const download = await request('GET', '/v1/snapshot', JSON.stringify({Authorization: `Bearer ${second.token}`}), null, 1000000);
    return {preserved, left, statuses: [create.status, upload.status, logout.status, login.status, download.status],
      restored: new TextDecoder().decode(download.bytes), revision: download.etag};
  }, {email, password, code, snapshot: sampleSnapshot()});
  assert.equal(result.preserved, 'fixture');
  assert.deepEqual(result.left, []);
  assert.deepEqual(result.statuses, [201, 204, 204, 200, 200]);
  assert.ok(result.restored.includes(taskTitle));
  assert.equal(result.revision, '"1"');
  const secondTab = await context.newPage();
  await secondTab.goto(`${origin}/storage-fixture`);
  assert.equal(await secondTab.evaluate(() => window.studentLifeStart()), 'already-open');
  await secondTab.close();
  await page.close();
  console.log('Chromium verified IndexedDB rename/purge, tab isolation, and HTTPS login → upload → logout → restore');
}

async function flutterApp(context) {
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', error => errors.push(String(error)));
  await page.goto(origin);
  await page.locator('flt-semantics-placeholder').waitFor({state: 'attached', timeout: 30000});
  await page.locator('flt-semantics-placeholder').dispatchEvent('click');
  const login = async () => {
    const emailField = page.getByRole('textbox', {name: /邮箱/});
    const passwordField = page.locator('flt-semantics input[type="password"], flt-semantics textarea[aria-label="密码"], flt-semantics [role="textbox"][aria-label="密码"]').first();
    await emailField.fill(email);
    await passwordField.fill(password);
    await page.getByRole('button', {name: '登录', exact: true}).click();
    await page.getByRole('button', {name: '退出账号', exact: true}).waitFor();
    await page.waitForFunction(async title => {
      const base = '/student-life/cloud-accounts';
      const paths = await window.studentLifeFile('list', base, null, null);
      for (const path of paths) {
        const data = `${base}/${path}/tasks.json`;
        if (await window.studentLifeFile('type', data, null, null) !== 'file') continue;
        const value = await window.studentLifeFile('read', data, null, null);
        if (new TextDecoder().decode(value).includes(title)) return true;
      }
      return false;
    }, taskTitle);
  };
  try {
    await page.getByRole('tab', {name: /我的/}).click();
    await page.getByRole('button', {name: /登录你的课屿账号/}).click();
    await login();
    await page.getByRole('button', {name: '退出账号', exact: true}).click();
    await page.getByRole('button', {name: '退出账号', exact: true}).last().click();
    await page.getByRole('button', {name: '登录', exact: true}).waitFor();
    const cachePaths = await page.evaluate(() => window.studentLifeFile('list', '/student-life/cloud-accounts', null, null));
    assert.equal(cachePaths.filter(path => /^[a-f0-9]{64}(?:\.signed-out)?$/.test(path)).length, 0);
    await login();
    assert.deepEqual(errors, []);
    console.log('Compiled Flutter UI signed in, restored shared cloud data, signed out, erased account cache, and restored again');
  } catch (error) {
    console.error('Chromium page errors:', errors);
    console.error('Flutter accessibility snapshot:', await page.locator('body').ariaSnapshot());
    throw error;
  } finally {
    await page.close();
  }
}

(async () => {
  const browser = await chromium.launch({executablePath: process.env.CHROMIUM ?? '/usr/bin/chromium'});
  try {
    const context = await browser.newContext({ignoreHTTPSErrors: true});
    await browserAdapter(context);
    await flutterApp(context);
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
