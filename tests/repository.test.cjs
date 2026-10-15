// Execute the actual Repository SQL against SQLite. The thin adapter models RDB
// call signatures; this is host SQLite integration, not a HarmonyOS runtime test.
const fs = require('fs'), path = require('path'), assert = require('assert/strict');
const { DatabaseSync } = require('node:sqlite');
const ts = require(process.env.TYPESCRIPT_PATH || 'C:/Program Files/Huawei/DevEco Studio/tools/hvigor/hvigor/node_modules/typescript');
const root = path.resolve(__dirname, '.tmp-rdb'); fs.mkdirSync(root, { recursive: true });
let db;
class Predicates { constructor(table) { this.table = table; } equalTo(key, value) { this.key = key; this.value = value; return this; } }
class RdbAdapter {
  constructor() { this.sqlite = new DatabaseSync(path.join(root, 'test.db')); }
  async executeSql(sql) { this.sqlite.exec(sql); }
  async querySql(sql) { const rows = this.sqlite.prepare(sql).all(); let index = -1; return { goToNextRow() { index++; return index < rows.length; }, getString() { return rows[index].payload; }, close() {} }; }
  async update(values, predicate) { const keys = Object.keys(values); return this.sqlite.prepare(`UPDATE ${predicate.table} SET ${keys.map(k => `${k}=?`).join(',')} WHERE ${predicate.key}=?`).run(...Object.values(values), predicate.value).changes; }
  async insert(table, values) { const keys = Object.keys(values); return this.sqlite.prepare(`INSERT INTO ${table} (${keys.join(',')}) VALUES (${keys.map(() => '?').join(',')})`).run(...Object.values(values)).lastInsertRowid; }
  async delete(predicate) { return this.sqlite.prepare(`DELETE FROM ${predicate.table} WHERE ${predicate.key}=?`).run(predicate.value).changes; }
  beginTransaction() { this.sqlite.exec('BEGIN'); } commit() { this.sqlite.exec('COMMIT'); } rollBack() { this.sqlite.exec('ROLLBACK'); }
}
const kit = { relationalStore: { SecurityLevel: { S3: 3 }, RdbPredicates: Predicates, async getRdbStore() { db = new RdbAdapter(); return db; } } };
function load(relative) { const source = fs.readFileSync(path.resolve(__dirname, relative),'utf8'); const js = ts.transpileModule(source,{ compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText; const m={exports:{}}; new Function('require','module','exports',js)(name => name === '../model/Domain' ? domain : kit,m,m.exports); return m.exports; }
const domain = load('../entry/src/main/ets/model/Domain.ets'); const { Repository } = load('../entry/src/main/ets/data/Repository.ets');
function item(kind,id,parent='') { const i=new domain.Item(); Object.assign(i,{kind,id,parent,name:id}); return i; }
let passed=0; async function test(name,action) { await action(); passed++; console.log(`PASS ${name}`); }
(async()=>{
 const repo=new Repository();await repo.open({});
 const c=item('Competition','competition'), t=item('Track','track',c.id), m=item('MaterialRequirement','material',t.id);
 await test('实际建表SQL创建11个表和父索引',async()=>{ assert.equal(db.sqlite.prepare("SELECT count(*) AS n FROM sqlite_master WHERE type='table'").get().n,11);assert.equal(db.sqlite.prepare("SELECT count(*) AS n FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%'").get().n,11); });
 await test('事务保存竞赛赛道材料与操作日志',async()=>{ await repo.save([c,t,m],'创建');const all=await repo.all();assert.equal(all.length,4);assert(all.some(i=>i.kind==='OperationLog')); });
 await test('父记录更新不会隐式删除子记录',async()=>{c.name='修改后的竞赛';await repo.save([c],'编辑');assert((await repo.all()).some(i=>i.id===t.id));});
 await test('SQL外键失败回滚整批数据和日志',async()=>{const before=(await repo.all()).length;await assert.rejects(repo.save([item('Competition','rolled-back'),item('Track','invalid','missing')],'失败批次'));assert.equal((await repo.all()).length,before);assert(!(await repo.all()).some(i=>i.id==='rolled-back'));});
 await test('删除存在子项的父实体被拒绝',async()=>assert.rejects(repo.remove(c)));
 await test('数据库层直接删除同样受外键保护',async()=>assert.throws(()=>db.sqlite.prepare('DELETE FROM Competition WHERE id=?').run(c.id)));
 const f=item('MaterialFile','file',m.id),v=item('FileVersion','version',m.id);v.source=f.id;m.current=v.id;
 await test('文件版本及当前指针原子写入',async()=>{await repo.save([f,v,m],'导入');assert.equal((await repo.all()).find(i=>i.id===m.id).current,v.id);});
 await test('历史版本与托管文件不可直接删除',async()=>{await assert.rejects(repo.remove(v));await assert.rejects(repo.remove(f));});
 await test('错误最终指针不能保存',async()=>{const bad=Object.assign(new domain.Item(),m,{final:'unknown'});await assert.rejects(repo.save([bad],'非法指针'));});
 await test('跨材料文件引用被拒绝',async()=>{const bad=item('FileVersion','wrong-version','other');bad.source=f.id;await assert.rejects(repo.save([bad],'错误关联'));});
 await test('无有效父项的任务被拒绝',async()=>assert.rejects(repo.save([item('Task','bad-task','missing')],'错误任务')));
 await test('关闭再打开SQLite保留全部记录',async()=>{const count=(await repo.all()).length;db.sqlite.close();const reopened=new Repository();await reopened.open({});assert.equal((await reopened.all()).length,count);assert.equal((await reopened.all()).find(i=>i.id===c.id).name,'修改后的竞赛');});
 console.log(`${passed} tests passed (actual SQL on host SQLite; not HarmonyOS RDB runtime)`);
})().catch(e=>{console.error(e);process.exitCode=1;}).finally(()=>{if(db)try{db.sqlite.close();}catch{}if(root===path.resolve(__dirname,'.tmp-rdb')&&root.startsWith(path.resolve(__dirname)+path.sep))fs.rmSync(root,{recursive:true,force:true});});
