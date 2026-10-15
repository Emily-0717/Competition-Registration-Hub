import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Item, TABLES, uid } from '../model/Domain';

export class Repository {
  private db: relationalStore.RdbStore | undefined = undefined;
  async open(context: common.UIAbilityContext): Promise<void> {
    this.db = await relationalStore.getRdbStore(context, { name: 'competitionhub.db', securityLevel: relationalStore.SecurityLevel.S3 });
    await this.db.executeSql('PRAGMA foreign_keys = ON');
    const parents: string[] = ['', 'Competition', 'Track', 'Track', 'MaterialRequirement', 'MaterialRequirement', 'Competition', '', 'Task', 'Track', ''];
    for (let n = 0; n < TABLES.length; n++) {
      const fk = parents[n] ? `, FOREIGN KEY(parent) REFERENCES ${parents[n]}(id) ON DELETE RESTRICT` : '';
      await this.db.executeSql(`CREATE TABLE IF NOT EXISTS ${TABLES[n]} (id TEXT PRIMARY KEY, parent TEXT NOT NULL, name TEXT NOT NULL, at INTEGER NOT NULL, payload TEXT NOT NULL ${fk})`);
      await this.db.executeSql(`CREATE INDEX IF NOT EXISTS idx_${TABLES[n]}_parent ON ${TABLES[n]}(parent)`);
    }
    this.db.version = 1;
  }
  private store(): relationalStore.RdbStore {
    if (!this.db) throw new Error('数据库未就绪');
    return this.db;
  }
  async all(): Promise<Item[]> {
    const items: Item[] = [];
    for (const table of TABLES) {
      const rs = await this.store().querySql(`SELECT payload FROM ${table} ORDER BY at DESC`);
      try { while (rs.goToNextRow()) items.push(JSON.parse(rs.getString(0)) as Item); }
      finally { rs.close(); }
    }
    return items;
  }
  private async write(item: Item): Promise<void> {
    if (!TABLES.includes(item.kind)) throw new Error('未知数据类型');
    const values: relationalStore.ValuesBucket = { id: item.id, parent: item.parent, name: item.name, at: item.at, payload: JSON.stringify(item) };
    const changed = await this.store().update(values, new relationalStore.RdbPredicates(item.kind).equalTo('id', item.id));
    if (changed === 0) await this.store().insert(item.kind, values);
  }
  async save(items: Item[], action: string): Promise<void> {
    const graph = (await this.all()).filter((i: Item) => !items.some((n: Item) => n.id === i.id)).concat(items);
    for (const item of items) {
      if (item.kind === 'FileVersion' && !graph.some((f: Item) => f.kind === 'MaterialFile' && f.id === item.source && f.parent === item.parent)) throw new Error('版本必须引用同一材料的文件');
      if (item.kind === 'MaterialRequirement') for (const id of [item.current, item.final]) {
        if (id && !graph.some((v: Item) => v.kind === 'FileVersion' && v.id === id && v.parent === item.id)) throw new Error('当前版或最终版关联无效');
      }
      if (item.kind === 'Task' && !graph.some((p: Item) => p.id === item.parent && ['Competition', 'Track', 'MaterialRequirement'].includes(p.kind))) throw new Error('任务必须关联有效竞赛、赛道或材料');
      if (item.kind === 'EligibilityRule' && item.current && !graph.some((m: Item) => m.id === item.current && m.kind === 'MaterialRequirement' && m.parent === item.parent)) throw new Error('资格证明必须关联同赛道材料');
    }
    const db = this.store(); db.beginTransaction();
    try {
      for (const item of items) await this.write(item);
      const log = new Item(); log.id = uid(); log.kind = 'OperationLog'; log.name = action;
      log.note = items.map((i: Item) => `${i.kind}:${i.id}`).join(','); await this.write(log);
      db.commit();
    } catch (e) { db.rollBack(); throw new Error((e as Error).message || JSON.stringify(e)); }
  }
  async remove(item: Item): Promise<void> {
    const all = await this.all();
    if (all.some((i: Item) => i.kind === 'EligibilityRule' && i.current === item.id)) throw new Error('材料仍被资格证明引用，请先解除关联');
    if (all.some((i: Item) => i.parent === item.id)) throw new Error('请先移除关联子项；历史版本和重要文件受保护');
    if (item.kind === 'FileVersion' || item.kind === 'MaterialFile') throw new Error('历史版本和托管文件禁止直接删除，请通过备份保留记录');
    const db = this.store(); db.beginTransaction();
    try {
      await db.delete(new relationalStore.RdbPredicates(item.kind).equalTo('id', item.id));
      const log = new Item(); log.id = uid(); log.kind = 'OperationLog'; log.name = '删除'; log.note = `${item.kind}:${item.id}`;
      await this.write(log); db.commit();
    } catch (e) { db.rollBack(); throw new Error((e as Error).message || JSON.stringify(e)); }
  }
  async backup(path: string): Promise<void> { await this.store().backup(path); }
  async restore(path: string): Promise<void> { await this.store().restore(path); }
}
