import { fileIo as fs, picker, fileUri } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { zlib } from '@kit.BasicServicesKit';
import { Item, FileCheck, uid, safeName } from '../model/Domain';

export class FileService {
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }
  private root(): string { return `${this.context.filesDir}/vault`; }
  private mkdir(path: string): void { if (!fs.accessSync(path)) fs.mkdirSync(path); }
  async hash(path: string): Promise<string> {
    const md = cryptoFramework.createMd('SHA256');
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const buffer = new ArrayBuffer(1024 * 1024);
      let read = fs.readSync(file.fd, buffer);
      while (read > 0) { await md.update({ data: new Uint8Array(buffer.slice(0, read)) }); read = fs.readSync(file.fd, buffer); }
      const digest = await md.digest(); return new util.Base64Helper().encodeToStringSync(digest.data);
    } finally { fs.closeSync(file); }
  }
  async importFile(material: Item, label: string, owner: string, note: string): Promise<Item[]> {
    const uris = await new picker.DocumentViewPicker(this.context).select({ maxSelectNumber: 1 });
    if (uris.length === 0) return [];
    const input = fs.openSync(uris[0], fs.OpenMode.READ_ONLY);
    this.mkdir(this.root());
    const file = new Item(); file.id = uid(); file.kind = 'MaterialFile'; file.parent = material.id;
    const uri = new fileUri.FileUri(uris[0]); file.name = uri.name;
    file.path = `${this.root()}/${file.id}`;
    try { fs.copyFileSync(input.fd, file.path); } finally { fs.closeSync(input); }
    try {
      const stat = fs.statSync(file.path); file.bytes = stat.size; file.modified = stat.mtime;
      file.hash = await this.hash(file.path);
      const version = new Item(); version.kind = 'FileVersion'; version.id = uid(); version.parent = material.id;
      version.name = label; version.source = file.id; version.owner = owner; version.note = note; version.status = '待审核';
      material.current = version.id; material.status = '准备中';
      return [file, version, material];
    } catch (e) { fs.unlinkSync(file.path); throw new Error((e as Error).message || JSON.stringify(e)); }
  }
  discard(items: Item[]): void {
    items.filter((i: Item) => i.kind === 'MaterialFile').forEach((i: Item) => { if (fs.accessSync(i.path)) fs.unlinkSync(i.path); });
  }
  async checks(all: Item[]): Promise<FileCheck[]> {
    const out: FileCheck[] = [];
    for (const file of all.filter((i: Item) => i.kind === 'MaterialFile')) {
      const c = new FileCheck(); c.id = file.id;
      try { c.bytes = fs.statSync(file.path).size; c.exists = true; c.intact = (await this.hash(file.path)) === file.hash; } catch (_) {}
      out.push(c);
    }
    return out;
  }
  writeText(path: string, text: string): void {
    const f = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try { fs.writeSync(f.fd, text); } finally { fs.closeSync(f); }
  }
  async saveFile(path: string, name: string): Promise<boolean> {
    const uris = await new picker.DocumentViewPicker(this.context).save({ newFileNames: [safeName(name)] });
    if (uris.length === 0) return false;
    const out = fs.openSync(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try { fs.copyFileSync(path, out.fd); } finally { fs.closeSync(out); }
    return true;
  }
  async open(file: Item): Promise<void> {
    await this.context.startAbility({ action: 'ohos.want.action.viewData', uri: fileUri.getUriFromPath(file.path), type: this.mime(file.name), flags: 1 });
  }
  mime(name: string): string {
    if (name.toLowerCase().endsWith('.pdf')) return 'application/pdf';
    if (name.toLowerCase().endsWith('.docx')) return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    if (name.toLowerCase().endsWith('.pptx')) return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    return 'application/octet-stream';
  }
  async package(track: Item, all: Item[], report: string): Promise<boolean> {
    const dir = `${this.context.cacheDir}/export-${uid()}`; this.mkdir(dir);
    const manifest: string[] = ['材料\t版本\t文件\t大小\tSHA-256\t修改人'];
    try {
      for (const m of all.filter((i: Item) => i.kind === 'MaterialRequirement' && i.parent === track.id)) {
        const v = all.find((i: Item) => i.kind === 'FileVersion' && i.id === m.final);
        if (!v) { if (m.required) throw new Error(`必填材料缺少最终版：${m.name}`); continue; }
        const f = all.find((i: Item) => i.kind === 'MaterialFile' && i.id === v.source);
        if (!f || await this.hash(f.path) !== f.hash) throw new Error(`文件完整性异常：${m.name}`);
        const name = `${safeName(m.name)}_${m.id.slice(-8)}_${safeName(v.name)}_${safeName(f.name)}`;
        fs.copyFileSync(f.path, `${dir}/${name}`);
        manifest.push([m.name, v.name, name, `${f.bytes}`, f.hash, v.owner].map((s: string) => s.replace(/[\t\r\n]/g, ' ')).join('\t'));
      }
      this.writeText(`${dir}/提交清单.tsv`, manifest.join('\n'));
      this.writeText(`${dir}/核验报告.txt`, report);
      const zip = `${dir}.zip`; await zlib.zipFile(dir, zip, {});
      try { return await this.saveFile(zip, `${safeName(track.name)}_提交资料.zip`); } finally { fs.unlinkSync(zip); }
    } finally { fs.rmdirSync(dir); }
  }
  async backup(dbPath: string): Promise<boolean> {
    const dir = `${this.context.cacheDir}/backup-${uid()}`; this.mkdir(dir);
    try {
      fs.copyFileSync(dbPath, `${dir}/competitionhub.db`);
      this.mkdir(`${dir}/vault`);
      if (fs.accessSync(this.root())) for (const name of fs.listFileSync(this.root())) fs.copyFileSync(`${this.root()}/${name}`, `${dir}/vault/${name}`);
      const zip = `${dir}.zip`; await zlib.zipFile(dir, zip, {});
      try { return await this.saveFile(zip, 'CompetitionHub_完整备份.zip'); } finally { fs.unlinkSync(zip); }
    } finally { fs.rmdirSync(dir); }
  }
  // Validate the ZIP central directory before extraction: only our DB and flat vault
  // entries are accepted; traversal, links, encryption, and oversized archives are rejected.
  private validateBackup(path: string): string {
    const size = fs.statSync(path).size;
    if (size > 2 * 1024 * 1024 * 1024) throw new Error('备份超过 2 GB，不能恢复');
    const f = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const tail = new ArrayBuffer(Math.min(size, 65557));
      fs.readSync(f.fd, tail, { offset: size - tail.byteLength });
      const view = new DataView(tail); let end = -1;
      for (let i = tail.byteLength - 22; i >= 0; i--) if (view.getUint32(i, true) === 0x06054b50) { end = i; break; }
      if (end < 0) throw new Error('无效 ZIP 备份');
      const count = view.getUint16(end + 10, true); const bytes = view.getUint32(end + 12, true); const offset = view.getUint32(end + 16, true);
      if (count > 10000 || bytes > 4 * 1024 * 1024 || offset + bytes > size) throw new Error('备份目录异常或 ZIP64 不受支持');
      const data = new ArrayBuffer(bytes); fs.readSync(f.fd, data, { offset }); const cv = new DataView(data);
      let pos = 0; let total = 0; let prefix = ''; let dbFound = false;
      const names: string[] = [];
      for (let n = 0; n < count; n++) {
        if (pos + 46 > bytes || cv.getUint32(pos, true) !== 0x02014b50) throw new Error('备份目录损坏');
        const len = cv.getUint16(pos + 28, true); const extra = cv.getUint16(pos + 30, true); const comment = cv.getUint16(pos + 32, true);
        if (pos + 46 + len + extra + comment > bytes) throw new Error('备份目录越界');
        const name = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(data.slice(pos + 46, pos + 46 + len)));
        if (name.includes('..') || name.includes('\\') || name.startsWith('/') || name.includes(':') || (cv.getUint16(pos + 8, true) & 1) !== 0 || ((cv.getUint32(pos + 38, true) >>> 16) & 0xF000) === 0xA000) throw new Error('备份含不安全路径或链接');
        if (names.includes(name)) throw new Error('备份含重复路径'); names.push(name);
        total += cv.getUint32(pos + 24, true); if (total > 2 * 1024 * 1024 * 1024) throw new Error('解压内容超过 2 GB');
        if (name.endsWith('competitionhub.db')) { prefix = name.slice(0, -17); dbFound = true; }
        pos += 46 + len + extra + comment;
      }
      if (!dbFound || (prefix && !/^backup-[a-zA-Z0-9-]+\/$/.test(prefix))) throw new Error('不是 CompetitionHub 备份');
      for (const name of names) {
        if (prefix && name === prefix) continue;
        if (!name.startsWith(prefix)) throw new Error('备份目录不一致');
        const rel = name.slice(prefix.length);
        if (rel !== 'competitionhub.db' && rel !== 'vault/' && !/^vault\/[a-zA-Z0-9-]+$/.test(rel)) throw new Error('备份包含未知文件');
      }
      return prefix;
    } finally { fs.closeSync(f); }
  }
  async chooseBackup(): Promise<string> {
    const uris = await new picker.DocumentViewPicker(this.context).select({ maxSelectNumber: 1 });
    if (!uris.length) return '';
    const zip = `${this.context.cacheDir}/restore-${uid()}.zip`;
    const source = fs.openSync(uris[0], fs.OpenMode.READ_ONLY);
    try { fs.copyFileSync(source.fd, zip); } finally { fs.closeSync(source); }
    const dir = zip.slice(0, -4); this.mkdir(dir);
    try { const prefix = this.validateBackup(zip); await zlib.unzipFile(zip, dir, {}); return `${dir}/${prefix}`; }
    catch (e) { fs.rmdirSync(dir); throw new Error((e as Error).message || JSON.stringify(e)); }
    finally { fs.unlinkSync(zip); }
  }
  async restoreFiles(dir: string, all: Item[]): Promise<Item[]> {
    this.mkdir(this.root());
    const out: Item[] = [];
    for (const file of all.filter((i: Item) => i.kind === 'MaterialFile')) {
      if (!/^[a-zA-Z0-9-]+$/.test(file.id)) throw new Error('备份文件 ID 无效');
      const source = `${dir}/vault/${file.id}`;
      if (await this.hash(source) !== file.hash) throw new Error(`备份文件校验失败：${file.name}`);
    }
    for (const file of all.filter((i: Item) => i.kind === 'MaterialFile')) {
      const dest = `${this.root()}/${file.id}`;
      if (fs.accessSync(dest) && await this.hash(dest) !== file.hash) throw new Error('备份与本地文件 ID 冲突，已阻止覆盖');
      if (!fs.accessSync(dest)) fs.copyFileSync(`${dir}/vault/${file.id}`, dest);
      file.path = dest; out.push(file);
    }
    return out;
  }
}
