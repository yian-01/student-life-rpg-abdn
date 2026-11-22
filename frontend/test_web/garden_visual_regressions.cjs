const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {chromium} = require('playwright');
const [origin, output] = process.argv.slice(2);
fs.mkdirSync(output, {recursive: true});
(async () => {
  const browser = await chromium.launch({executablePath: process.env.CHROMIUM});
  const context = await browser.newContext({ignoreHTTPSErrors: origin.includes('127.0.0.1'), viewport: {width: 1440, height: 900}});
  const page = await context.newPage();
  const errors = [], checks = [];
  page.on('pageerror', e => errors.push(String(e)));
  function passed(name) {
    checks.push(name);
    fs.writeFileSync(path.join(output, 'checks.json'), JSON.stringify({checks, errors}, null, 2));
  }
  try {
    await page.goto(origin);
    await page.locator('flt-semantics-placeholder').waitFor({state: 'attached', timeout: 45000});
    await page.locator('flt-semantics-placeholder').dispatchEvent('click');
    const brand = page.getByRole('button', {name: 'KEYU', exact: true});
    await brand.click();
    await page.getByRole('button', {name: /首页/}).waitFor();
    await page.screenshot({path: path.join(output, 'navigation-light.png')});
    await page.getByRole('button', {name: '切换深色', exact: true}).click();
    await page.screenshot({path: path.join(output, 'navigation-dark.png')});
    await page.getByRole('button', {name: '切换浅色', exact: true}).click();
    passed('Both navigation themes render with the original footprint');
    await page.getByRole('button', {name: '互动设置', exact: true}).click();
    const sliders = page.getByRole('slider');
    await sliders.first().waitFor();
    await page.waitForTimeout(500);
    assert.equal(await sliders.count(), 2);
    for (const slider of await sliders.all()) assert.ok((await slider.boundingBox()).height <= 52);
    const thumb = await sliders.first().boundingBox();
    await page.mouse.click(thumb.x + thumb.width / 2 + 85, thumb.y + thumb.height / 2);
    await page.waitForTimeout(200);
    assert.match(await page.locator('body').ariaSnapshot(), /风速 [1-9][0-9]*%/);
    await page.getByRole('button', {name: '风暴', exact: true}).click();
    await page.screenshot({path: path.join(output, 'settings-fixed.png')});
    await page.getByRole('button', {name: '跟随页面', exact: true}).click();
    const group = page.getByRole('button', {name: '三株并置', exact: true});
    await group.click();
    await page.getByRole('button', {name: '三株并置', exact: true}).waitFor();
    await page.getByRole('button', {name: '三株并置', exact: true}).click();
    await page.getByRole('button', {name: '单株试验场', exact: true}).click();
    await page.getByRole('button', {name: '下一株', exact: true}).click();
    await page.getByRole('button', {name: '上一株', exact: true}).click();
    await page.getByRole('button', {name: '单株试验场', exact: true}).click();
    await page.getByRole('button', {name: '跟随页面', exact: true}).click();
    passed('Compact wind controls and all scene menu choices work without overlay errors');
    await page.getByRole('button', {name: '收起', exact: true}).click();
    await page.getByRole('button', {name: '互动像素植物', exact: true}).click();
    await page.waitForTimeout(1500);
    await page.screenshot({path: path.join(output, 'pixel-leaves.png')});
    await page.waitForTimeout(2500);
    await page.screenshot({path: path.join(output, 'pixel-leaves-later.png')});
    assert.deepEqual(errors, []);
    passed('Animated plant interaction and pixel leaf frames render without browser exceptions');
    console.log(JSON.stringify({passed: checks.length, checks, errors}));
  } catch (error) {
    await page.screenshot({path: path.join(output, 'failure.png')}).catch(() => {});
    console.error(await page.locator('body').ariaSnapshot());
    throw error;
  } finally {
    await context.close(); await browser.close();
  }
})().catch(e => {console.error(e);process.exitCode = 1;});
