export const TABLES: string[] = ['Competition', 'Track', 'EligibilityRule', 'MaterialRequirement', 'MaterialFile', 'FileVersion', 'TeamMember', 'Task', 'Reminder', 'VerificationResult', 'OperationLog'];

export class Item {
  id: string = '';
  kind: string = 'Competition';
  parent: string = '';
  name: string = '';
  note: string = '';
  source: string = '';
  status: string = '未开始';
  owner: string = '';
  due: string = '';
  start: string = '';
  organizer: string = '';
  category: string = '';
  level: string = '';
  url: string = '';
  required: boolean = true;
  formats: string = 'pdf,docx';
  maxMB: number = 50;
  path: string = '';
  bytes: number = 0;
  modified: number = 0;
  hash: string = '';
  current: string = '';
  final: string = '';
  priority: string = '普通';
  at: number = Date.now();
  sent: boolean = false;
}

export class Finding {
  level: string = '警告';
  target: string = '';
  message: string = '';
  human: boolean = false;
  constructor(level: string, target: string, message: string, human: boolean = false) {
    this.level = level; this.target = target; this.message = message; this.human = human;
  }
}

export class FileCheck {
  id: string = '';
  exists: boolean = false;
  intact: boolean = false;
  bytes: number = 0;
}

export class Readiness {
  score: number = 0;
  reasons: string[] = [];
}
export function readiness(track: Item, all: Item[], now: number): Readiness {
  const r = new Readiness();
  const materials = all.filter((i: Item) => i.kind === 'MaterialRequirement' && i.parent === track.id);
  const required = materials.filter((i: Item) => i.required);
  const rules = all.filter((i: Item) => i.kind === 'EligibilityRule' && i.parent === track.id);
  const linked = required.length ? required.filter((m: Item) => all.some((v: Item) => v.kind === 'FileVersion' && v.parent === m.id)).length / required.length : 0;
  const reviewed = required.length ? required.filter((m: Item) => m.status === '已完成').length / required.length : 0;
  const eligible = rules.length ? rules.filter((i: Item) => i.status === '符合').length / rules.length : 0;
  const final = required.length ? required.filter((m: Item) => !!m.final).length / required.length : 0;
  r.score = Math.round(linked * 40 + reviewed * 25 + eligible * 20 + final * 15);
  r.reasons.push(`必填材料有版本 ${Math.round(linked * 100)}% × 40%；审核完成 ${Math.round(reviewed * 100)}% × 25%`);
  r.reasons.push(`资格已确认 ${Math.round(eligible * 100)}% × 20%；最终版指定 ${Math.round(final * 100)}% × 15%`);
  if (!required.length) r.reasons.push('缺少必填材料规则：材料部分按零分计');
  if (!rules.length) r.reasons.push('缺少资格规则：资格部分按零分计');
  if (rules.some((i: Item) => i.status === '不符合')) { r.score = Math.min(49, r.score); r.reasons.push('存在明确不符合资格，准备度上限 49 分'); }
  if (track.due) {
    const left = new Date(track.due).getTime() - now;
    if (left < 0) { r.score = 0; r.reasons.push('已过赛道截止日期，时间风险将准备度降为零'); }
    else if (left < 3 * 86400000 && r.score < 100) { r.score = Math.min(69, r.score); r.reasons.push('三天内截止且仍有待办，准备度上限 69 分'); }
  } else r.reasons.push('未设置赛道截止日期，时间风险尚未确认');
  r.reasons.push('准备度反映记录状态，不能替代文件完整性核验或人工签章确认');
  return r;
}

export function uid(): string { return `${Date.now()}-${Math.random().toString(36).slice(2, 12)}`; }
export function percent(items: Item[]): number {
  return items.length === 0 ? 0 : Math.round(items.filter((i: Item) => i.status === '已完成').length * 100 / items.length);
}
export function safeName(name: string): string {
  return name.replace(/[\\/:*?"<>|\x00-\x1f]/g, '_').replace(/^\.+/, '_').slice(0, 100) || '材料';
}
export function extension(name: string): string { return name.includes('.') ? name.split('.').pop()!.toLowerCase() : ''; }

// Pure rule evaluation: signatures and authenticity always remain human decisions.
export function verify(track: Item, all: Item[], checks: FileCheck[], now: number): Finding[] {
  const result: Finding[] = [];
  const materials = all.filter((i: Item) => i.kind === 'MaterialRequirement' && i.parent === track.id);
  const rules = all.filter((i: Item) => i.kind === 'EligibilityRule' && i.parent === track.id);
  if (materials.length === 0) result.push(new Finding('未通过', track.name, '尚未配置材料要求'));
  if (rules.length === 0) result.push(new Finding('警告', track.name, '尚未建立资格条件清单', true));
  rules.forEach((r: Item) => {
    if (r.status !== '符合') result.push(new Finding(r.status === '不符合' ? '未通过' : '警告', r.name, `资格状态：${r.status}`, true));
  });
  materials.forEach((m: Item) => {
    if (m.required && m.status !== '已完成') result.push(new Finding('未通过', m.name, '必填材料尚未完成审核'));
    const versions = all.filter((v: Item) => v.kind === 'FileVersion' && v.parent === m.id);
    const final = versions.find((v: Item) => v.id === m.final);
    if (!final) {
      if (m.required) result.push(new Finding('未通过', m.name, '未指定最终提交版本'));
      else result.push(new Finding('警告', m.name, '选填材料未提供，导出将跳过'));
      return;
    }
    const file = all.find((f: Item) => f.kind === 'MaterialFile' && f.id === final.source);
    const check = checks.find((c: FileCheck) => c.id === final.source);
    if (!file || !check || !check.exists) result.push(new Finding('未通过', m.name, '最终版本文件不存在或不可访问'));
    else {
      if (!check.intact) result.push(new Finding('未通过', m.name, 'SHA-256 完整性检查失败'));
      if (check.bytes > m.maxMB * 1024 * 1024) result.push(new Finding('未通过', m.name, `文件超过 ${m.maxMB} MB`));
      const accepted = m.formats.toLowerCase().split(',').map((s: string) => s.trim().replace(/^\./, ''));
      if (m.formats.trim() && !accepted.includes(extension(file.name))) result.push(new Finding('未通过', m.name, '文件扩展名不符合要求（内容格式仍需人工复核）'));
    }
    if (versions.filter((v: Item) => v.status === '待审核').length > 1) result.push(new Finding('警告', m.name, '多个版本待审核，请明确审核结论'));
    result.push(new Finding('警告', m.name, '请人工确认内容、签章、原创性及实际文件格式', true));
  });
  const scope = [track.id, track.parent].concat(materials.map((m: Item) => m.id));
  all.filter((t: Item) => t.kind === 'Task' && scope.includes(t.parent) && t.status !== '已完成' && t.due !== '').forEach((t: Item) => {
    const left = new Date(t.due).getTime() - now;
    if (left <= 3 * 86400000) result.push(new Finding('警告', t.name, left < 0 ? '任务已逾期' : '任务将在三天内截止'));
  });
  if (track.due && new Date(track.due).getTime() < now) result.push(new Finding('未通过', track.name, '赛道提交截止日期已过'));
  if (!result.some((f: Finding) => f.level === '未通过')) result.unshift(new Finding('通过', track.name, '已满足当前可自动核验的要求；人工事项请逐项确认'));
  return result;
}
