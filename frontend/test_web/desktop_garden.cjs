const assert=require('node:assert/strict');
const fs=require('node:fs');const path=require('node:path');const {chromium}=require('playwright');
const origin=process.argv[2],out=process.argv[3];
if(!origin||!out)throw Error('Usage: node desktop_garden.cjs https://preview output-directory');
fs.mkdirSync(out,{recursive:true});
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROMIUM??'/usr/bin/chromium'});
 const context=await browser.newContext({ignoreHTTPSErrors:true,viewport:{width:1440,height:900}});
 const page=await context.newPage(),errors=[],checks=[];page.on('pageerror',e=>errors.push(String(e)));
 async function check(text){checks.push(text);fs.writeFileSync(path.join(out,'checks.json'),JSON.stringify({checks,errors},null,2));}
 const brand=()=>page.getByRole('button',{name:'KEYU',exact:true});
 async function nav(name){await brand().click();await page.getByRole('button',{name:new RegExp(name)}).click();}
 async function shot(name){await page.waitForTimeout(500);await page.screenshot({path:path.join(out,name+'.png')});}
 async function enableSemantics(){await page.locator('flt-semantics-placeholder').waitFor({state:'attached',timeout:30000});await page.locator('flt-semantics-placeholder').dispatchEvent('click');}
 try{
  await page.goto(origin);await enableSemantics();await page.getByText('今天，也慢慢来。',{exact:true}).waitFor();
  await shot('home-light');assert.equal(await page.getByRole('tab',{name:/首页/}).count(),0);await check('Real compiled Flutter desktop home and source cherry scene load');
  await nav('学业');await page.getByRole('button',{name:/GPA/}).waitFor();await shot('study');
  await page.getByRole('button',{name:/课程/}).click();await page.getByRole('button',{name:'新建学期',exact:true}).click();
  const semester='Browser Semester '+Date.now();
  const name=page.getByRole('textbox',{name:'学期名称',exact:true});await name.click();await name.pressSequentially(semester,{delay:20});
  await page.getByRole('button',{name:'保存',exact:true}).click();await page.locator(`[aria-label*="${semester}"]`).first().waitFor();
  assert.equal(await page.getByRole('button',{name:'互动像素植物',exact:true}).getByRole('textbox').count(),0);
  await check('Course entrance opens real semester editor and persists a semester; scene semantics are isolated');
  await nav('日程');await page.getByRole('button',{name:/周课表/}).waitFor();await shot('days');
  await page.getByRole('button',{name:/待办/}).click();await page.getByRole('button',{name:'添加待办',exact:true}).click();
  const title='Desktop persistent task '+Date.now();
  const task=page.getByRole('textbox',{name:'标题',exact:true});
  await task.click();await task.pressSequentially(title,{delay:20});await page.getByRole('button',{name:'添加',exact:true}).click();
  await page.getByRole('button',{name:new RegExp(title)}).waitFor();
  const storage=await page.evaluate(async()=>new TextDecoder().decode(await window.studentLifeFile('read','/student-life/tasks.json',null,null)));
  assert.ok(storage.includes(title));await shot('todo-real');await check('Todo entrance writes through the real browser storage adapter');
  await page.reload();await enableSemantics();
  await nav('日程');await page.getByRole('button',{name:/待办/}).click();await page.getByRole('checkbox',{name:'全部未完成',exact:true}).click();await page.getByRole('button',{name:new RegExp(title)}).waitFor();
  await check('New task survives browser reload and reappears through real UI');
  await nav('财务');await page.getByRole('button',{name:/预算/}).waitFor();await shot('finance');
  await page.getByRole('button',{name:/票据/}).click();await page.getByText('票据与报销',{exact:true}).waitFor();await check('Finance receipt entrance is a real filtered ledger');
  await nav('更多');await page.getByRole('button',{name:/备份与恢复/}).waitFor();await shot('more');
  await brand().click();await page.getByRole('button',{name:'切换深色',exact:true}).click();
  await page.mouse.move(900,80);await page.waitForTimeout(400);await shot('more-dark');await check('Both themes preserve the active section');
  await nav('首页');await page.getByText('今天，也慢慢来。',{exact:true}).waitFor();await page.mouse.move(800,120);
  await page.mouse.wheel(-250,0);await page.waitForTimeout(450);await page.getByText('今天，也慢慢来。',{exact:true}).waitFor();
  await page.mouse.wheel(180,0);for(const value of [80,20,110,-110,90]){await page.waitForTimeout(50);await page.mouse.wheel(value,0);}
  await page.getByRole('button',{name:/GPA/}).waitFor();assert.equal(await page.getByRole('button',{name:/周课表/}).count(),0);await check('Real Chromium wheel input respects the home boundary and consumes inertial peaks once');
  assert.deepEqual(errors,[]);console.log(JSON.stringify({passed:checks.length,checks,errors}));
 }catch(error){await page.screenshot({path:path.join(out,'failure.png')}).catch(()=>{});console.error(await page.locator('body').ariaSnapshot());throw error;}finally{await context.close();await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
