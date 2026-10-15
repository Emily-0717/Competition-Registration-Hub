const fs=require('fs'),path=require('path'),assert=require('assert/strict');
const ts=require(process.env.TYPESCRIPT_PATH || 'C:/Program Files/Huawei/DevEco Studio/tools/hvigor/hvigor/node_modules/typescript');
const base=path.resolve(__dirname,'../entry/src/main/ets');
let passed=0;
async function test(name,fn){await fn();passed++;console.log(`PASS ${name}`);}
const source=fs.readFileSync(path.join(base,'services/PdfCapability.ets'),'utf8');
const js=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText;
async function evaluate(capability,loader){const m={exports:{}};new Function('require','module','exports','canIUse',js)(loader,m,m.exports,()=>capability);return m.exports.hasPdfPreview();}
(async()=>{
 await test('PDF能力不存在时不触发模块加载',async()=>{let count=0;assert.equal(await evaluate(false,()=>{count++;return {};}),false);assert.equal(count,0);});
 await test('模拟器缺少命名导出时安全降级',async()=>assert.equal(await evaluate(true,()=>({PdfView:{}})),false));
 await test('PDF模块加载异常被捕获',async()=>assert.equal(await evaluate(true,()=>{throw new SyntaxError('missing module');}),false));
 await test('PDF完整能力通过后方可进入预览',async()=>assert.equal(await evaluate(true,()=>({pdfViewManager:{PdfController:class {}},PdfView:{}})),true));
 await test('首页静态依赖图不链接可选PDF模块',async()=>{
  const visited=new Set();
  function walk(p){if(visited.has(p))return;visited.add(p);const text=fs.readFileSync(p,'utf8');const file=ts.createSourceFile(p,text,ts.ScriptTarget.Latest,true,ts.ScriptKind.TS);
   for(const node of file.statements){if(!ts.isImportDeclaration(node))continue;const name=node.moduleSpecifier.text;assert(!name.includes('PDFKit')&&!name.includes('officeservice.PdfView'),`startup module ${p} statically links ${name}`);if(name.startsWith('.'))walk(path.resolve(path.dirname(p),name+'.ets'));}
  }
  walk(path.join(base,'pages/Index.ets'));walk(path.join(base,'entryability/EntryAbility.ets'));
 });
 console.log(`${passed} tests passed (startup dependency and runtime export regressions)`);
})().catch(e=>{console.error(e);process.exitCode=1;});
