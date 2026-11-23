const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {chromium} = require('playwright');
const origin = process.argv[2], output = process.argv[3];
const apiOrigin = process.argv[4] ?? origin;
if (!origin || !output) throw Error('Usage: node social.cjs https://origin output-directory');
fs.mkdirSync(output, {recursive: true});
const local = new URL(origin).hostname === '127.0.0.1';
const code = local ? 'student-life-fixture' : '';
const nonce = Date.now(), errors = [], checks = [], identities = [];
function passed(text) {
  checks.push(text);
  fs.writeFileSync(path.join(output, 'checks.json'), JSON.stringify({origin, checks, errors}, null, 2));
  console.log('PASS ' + text);
}
async function enter(field, value) {
  await field.click(); await field.fill(value);
  assert.equal(await field.inputValue(), value);
}
async function visibleMessage(page, text) {
  await page.bringToFront();
  for (let attempt=0; attempt<80; attempt++) {
    if ((await page.locator('body').ariaSnapshot()).includes(text)) return;
    await page.waitForTimeout(250);
  }
  throw Error('Expected private message did not render');
}
async function space(page) {
  await page.getByRole('button', {name:/个人空间与好友/}).click();
  await page.getByRole('button', {name:'保存个人资料', exact:true}).waitFor();
  for (let i=0; !page.profile && i<50; i++) await page.waitForTimeout(100);
  assert.ok(page.profile?.id);
}
async function start(browser, suffix) {
  const context = await browser.newContext({ignoreHTTPSErrors:local, viewport:{width:1440,height:900}});
  const page = await context.newPage();
  page.on('pageerror', e=>errors.push(String(e)));
  page.on('response', async r=>{
    if (!r.ok()) return;
    if (/\/v1\/(register|login)$/.test(r.url())) page.auth=await r.json();
    if (r.url().endsWith('/v1/profile')) page.profile=await r.json();
  });
  await page.goto(origin);
  await page.locator('flt-semantics-placeholder').waitFor({state:'attached',timeout:45000});
  await page.locator('flt-semantics-placeholder').dispatchEvent('click');
  await page.getByRole('button',{name:'KEYU',exact:true}).click();
  await page.getByRole('button',{name:'我的账号',exact:true}).click();
  await page.getByRole('button',{name:'注册账号',exact:true}).click();
  const email=`social-${suffix}-${nonce}@example.test`;
  await enter(page.getByRole('textbox',{name:'邮箱',exact:true}),email);
  const protectedFields=page.locator('flt-semantics input[type="password"]');
  await enter(protectedFields.first(),'eight888');
  if (code) await enter(protectedFields.nth(1),code);
  else assert.equal(await protectedFields.nth(1).inputValue(),'');
  await page.getByRole('button',{name:'注册并登录',exact:true}).click();
  await page.getByRole('button',{name:'退出账号',exact:true}).waitFor({timeout:30000});
  assert.ok(page.auth?.id);
  identities.push({id:page.auth.id,email});
  fs.writeFileSync(path.join(output,'test-accounts.json'),JSON.stringify({origin,accounts:identities},null,2));
  await space(page);
  return {context,page};
}
(async()=>{
  const browser=await chromium.launch({executablePath:process.env.CHROMIUM??'/usr/bin/chromium'});
  const clients=[];
  try {
    const a=await start(browser,'a');clients.push(a);
    const b=await start(browser,'b');clients.push(b);
    assert.notEqual(a.page.profile.id,b.page.profile.id);
    passed('Two isolated accounts register with eight-character passwords and receive unique public IDs');
    await enter(a.page.getByRole('textbox',{name:'昵称',exact:true}),'星夜同学');
    await a.page.getByRole('button',{name:'保存个人资料',exact:true}).click();
    await a.page.getByText('个人资料已保存',{exact:true}).waitFor();
    await a.page.screenshot({path:path.join(output,'profile-desktop.png')});
    passed('Profile edits persist through the real account API');
    await a.page.getByRole('tab',{name:/好友 ·/}).click();
    await enter(a.page.getByRole('textbox',{name:/好友 ID/}),b.page.profile.id);
    await a.page.getByRole('button',{name:'查找好友',exact:true}).click();
    await a.page.getByRole('button',{name:'添加好友',exact:true}).click();
    await a.page.getByRole('button',{name:'已申请',exact:true}).waitFor();
    await b.page.getByRole('button',{name:'刷新个人空间',exact:true}).click();
    await b.page.getByRole('tab',{name:'申请 · 1',exact:true}).click();
    await b.page.getByRole('button',{name:'接受',exact:true}).click();
    await b.page.getByRole('tab',{name:'好友 · 1',exact:true}).waitFor();
    await b.page.getByRole('tab',{name:/好友 ·/}).click();
    await b.page.getByRole('button',{name:'私信',exact:true}).waitFor();
    await b.page.screenshot({path:path.join(output,'friends-desktop.png')});
    passed('Public-ID lookup, friend request and recipient acceptance create mutual friendship');
    await a.page.getByRole('button',{name:'刷新个人空间',exact:true}).click();
    await a.page.getByRole('button',{name:'私信',exact:true}).click();
    await b.page.getByRole('button',{name:'私信',exact:true}).click();
    const first='你好，今天一起复习吗？'+nonce;
    await enter(a.page.getByRole('textbox',{name:/输入私信/}),first);
    await a.page.getByRole('button',{name:'发送',exact:true}).click();
    await visibleMessage(b.page,first);
    const answer='好呀，下午四点见！'+nonce;
    await enter(b.page.getByRole('textbox',{name:/输入私信/}),answer);
    await b.page.getByRole('button',{name:'发送',exact:true}).click();
    await visibleMessage(a.page,answer);
    await a.page.screenshot({path:path.join(output,'chat-desktop.png')});
    passed('Both friends send and receive real stored private messages');
    await b.page.setViewportSize({width:390,height:844});
    await visibleMessage(b.page,first);
    await b.page.screenshot({path:path.join(output,'chat-phone.png')});
    const headers={Authorization:'Bearer '+a.page.auth.token};
    const profile=await a.context.request.get(apiOrigin+'/v1/profile',{headers});
    const data=await profile.json();
    assert.equal(data.nickname,'星夜同学');
    assert.ok(!('email' in data)&&!('token' in data));
    assert.deepEqual(errors,[]);
    passed('Phone-width chat remains usable and profile responses exclude email and credentials');
  } catch(e) {
    for(let i=0;i<clients.length;i++) {
      await clients[i].page.screenshot({path:path.join(output,`failure-${i}.png`)}).catch(()=>{});
      fs.writeFileSync(path.join(output,`failure-${i}.txt`),await clients[i].page.locator('body').ariaSnapshot());
    }
    throw e;
  } finally {
    for(const c of clients) await c.context.close();
    await browser.close();
  }
})().catch(e=>{console.error(e);process.exitCode=1;});
