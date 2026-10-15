const fs = require('fs'), path = require('path'), crypto = require('crypto'), assert = require('assert/strict');
const ts = require(process.env.TYPESCRIPT_PATH || 'C:/Program Files/Huawei/DevEco Studio/tools/hvigor/hvigor/node_modules/typescript');
const root = path.resolve(__dirname, '.tmp-files'); fs.mkdirSync(root, { recursive: true });
const context = { filesDir: root, cacheDir: root };
let choice = [];
const nativeFs = {
  OpenMode: { READ_ONLY: 'r' },
  accessSync: fs.existsSync, mkdirSync: fs.mkdirSync, unlinkSync: fs.unlinkSync,
  openSync(p, mode) { return { fd: fs.openSync(p, mode) }; }, closeSync(f) { fs.closeSync(f.fd); },
  statSync(p) { const s = fs.statSync(p); return { size: s.size, mtime: s.mtimeMs / 1000 }; },
  copyFileSync(src, dst) { fs.writeFileSync(dst, fs.readFileSync(src)); },
  readSync(fd, buffer, options) { return fs.readSync(fd, new Uint8Array(buffer), 0, buffer.byteLength, options?.offset ?? null); }
};
const kits = {
  '@kit.CoreFileKit': { fileIo: nativeFs, picker: { DocumentViewPicker: class { async select() { return choice; } } }, fileUri: { FileUri: class { constructor(p) { this.name = path.basename(p); } } } },
  '@kit.CryptoArchitectureKit': { cryptoFramework: { createMd() { const md = crypto.createHash('sha256'); return { async update(b) { md.update(b.data); }, async digest() { return { data: md.digest() }; } }; } } },
  '@kit.ArkTS': { util: { Base64Helper: class { encodeToStringSync(d) { return Buffer.from(d).toString('base64'); } }, TextDecoder: { create() { return { decodeToString(d) { return Buffer.from(d).toString('utf8'); } }; } } } },
  '@kit.BasicServicesKit': { zlib: {} }, '@kit.AbilityKit': {}
};
function load(relative) {
  const s = fs.readFileSync(path.resolve(__dirname, relative), 'utf8');
  const js = ts.transpileModule(s, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
  const m = { exports: {} }; new Function('require', 'module', 'exports', js)(name => name === '../model/Domain' ? domain : kits[name], m, m.exports); return m.exports;
}
const domain = load('../entry/src/main/ets/model/Domain.ets');
const { FileService } = load('../entry/src/main/ets/services/FileService.ets');
const service = new FileService(context); let passed = 0;
async function test(name, fn) { await fn(); passed++; console.log(`PASS ${name}`); }
function zipDirectory(entries) {
  const chunks = entries.map(e => { const n = Buffer.from(e.name); const h = Buffer.alloc(46); h.writeUInt32LE(0x02014b50); h.writeUInt32LE(e.size || 0, 24); h.writeUInt16LE(n.length, 28); h.writeUInt32LE(e.link ? 0xA0000000 : 0, 38); return Buffer.concat([h, n]); });
  const body = Buffer.concat(chunks); const end = Buffer.alloc(22); end.writeUInt32LE(0x06054b50); end.writeUInt16LE(entries.length, 10); end.writeUInt32LE(body.length, 12);
  const p = path.join(root, 'directory.zip'); fs.writeFileSync(p, Buffer.concat([body, end])); return p;
}
(async () => {
  await test('真实文件流 SHA-256 跨越多个缓冲块', async () => { const p = path.join(root, 'large.bin'); const bytes = crypto.randomBytes(2 * 1024 * 1024 + 19); fs.writeFileSync(p, bytes); assert.equal(await service.hash(p), crypto.createHash('sha256').update(bytes).digest('base64')); });
  await test('取消选择不产生文件或版本', async () => { choice = []; assert.deepEqual(await service.importFile(new domain.Item(), 'V1', '甲', ''), []); });
  await test('导入复制文件并独立创建版本', async () => { const src = path.join(root, 'input.pdf'); fs.writeFileSync(src, 'original'); choice = [src]; const m = new domain.Item(); m.id = 'material'; const result = await service.importFile(m, 'V1', '甲', '草稿'); assert.equal(result.length, 3); const file = result[0]; fs.writeFileSync(src, 'edited externally'); assert.equal(fs.readFileSync(file.path, 'utf8'), 'original'); assert.equal(result[1].source, file.id); assert.equal(result[2].current, result[1].id); });
  await test('缺失文件检查返回明确失败', async () => { const f = new domain.Item(); f.kind = 'MaterialFile'; f.id = 'missing'; f.path = path.join(root, 'missing'); const c = await service.checks([f]); assert.equal(c[0].exists, false); });
  await test('接受自身备份的平面目录', async () => { assert.equal(service.validateBackup(zipDirectory([{ name: 'competitionhub.db' }, { name: 'vault/' }, { name: 'vault/123-abc' }])),''); });
  await test('接受包含根目录的备份', async () => { assert.equal(service.validateBackup(zipDirectory([{ name: 'backup-123/' }, { name: 'backup-123/competitionhub.db' }, { name: 'backup-123/vault/' }])),'backup-123/'); });
  await test('拒绝 ZIP 路径穿越', async () => assert.throws(() => service.validateBackup(zipDirectory([{ name: 'competitionhub.db' }, { name: '../escape' }]))));
  await test('拒绝 ZIP 符号链接', async () => assert.throws(() => service.validateBackup(zipDirectory([{ name: 'competitionhub.db' }, { name: 'vault/link', link: true }]))));
  await test('拒绝异常解压大小', async () => assert.throws(() => service.validateBackup(zipDirectory([{ name: 'competitionhub.db', size: 0xffffffff }]))));
  await test('拒绝未知备份文件和重复条目', async () => { assert.throws(() => service.validateBackup(zipDirectory([{ name: 'competitionhub.db' }, { name: 'script.js' }]))); assert.throws(() => service.validateBackup(zipDirectory([{ name: 'competitionhub.db' }, { name: 'competitionhub.db' }]))); });
  console.log(`${passed} tests passed (Node file adapters; not HarmonyOS device tests)`);
})().catch(e => { console.error(e); process.exitCode = 1; }).finally(() => { if (root === path.resolve(__dirname, '.tmp-files') && root.startsWith(path.resolve(__dirname) + path.sep)) fs.rmSync(root, { recursive: true, force: true }); });
