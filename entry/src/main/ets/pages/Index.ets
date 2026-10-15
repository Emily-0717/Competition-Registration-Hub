import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { PdfPreviewParams } from '../model/PreviewParams';
import { hasPdfPreview } from '../services/PdfCapability';
import { Item, Finding, TABLES, uid, percent, verify, extension, readiness } from '../model/Domain';
import { Repository } from '../data/Repository';
import { FileService } from '../services/FileService';

@Entry
@Component
struct Index {
  @State items: Item[] = [];
  @State page: number = 0;
  @State query: string = '';
  @State selected: string = '';
  @State competition: string = '';
  @State track: string = '';
  @State message: string = '正在打开本地资料库…';
  @State busy: boolean = true;
  @State editing: boolean = false;
  @State draft: Item = new Item();
  @State findings: Finding[] = [];
  @State preview: string = '';
  @State previewType: string = '';
  @State grid: boolean = false;
  @State filter: string = '全部';
  @State descending: boolean = true;
  @State calendar: boolean = false;
  @State month: number = new Date().getMonth();
  @State year: number = new Date().getFullYear();
  @State viewport: number = 1440;
  private repo: Repository = new Repository();
  private files: FileService | undefined = undefined;
  private context: common.UIAbilityContext | undefined = undefined;
  private timer: number = -1;
  private navigation: string[] = ['总览工作台', '我的竞赛', '赛道管理', '报名资格', '材料清单', '文件资料库', '版本历史', '提交核验', '日历与提醒', '设置'];
  private kinds: string[] = ['', 'Competition', 'Track', 'EligibilityRule', 'MaterialRequirement', 'MaterialFile', 'FileVersion', 'VerificationResult', 'Task', ''];

  aboutToAppear(): void {
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.files = new FileService(this.context);
    this.run(async () => { await this.repo.open(this.context!); await this.reload(); this.message = '资料已安全保存在本机'; });
    this.timer = setInterval(() => { if (!this.busy) this.run(async () => this.remind()); }, 60000);
  }
  aboutToDisappear(): void { if (this.timer !== -1) clearInterval(this.timer); }
  private async reload(): Promise<void> {
    this.items = await this.repo.all();
    if (!this.competition) this.competition = this.items.find((i: Item) => i.kind === 'Competition')?.id || '';
    if (!this.track) this.track = this.items.find((i: Item) => i.kind === 'Track' && i.parent === this.competition)?.id || '';
  }
  private async run(action: () => Promise<void>): Promise<void> {
    if (this.busy && this.files === undefined) return;
    this.busy = true;
    try { await action(); }
    catch (e) { this.message = `操作失败：${(e as Error).message || JSON.stringify(e)}`; }
    finally { this.busy = false; }
  }
  private async remind(): Promise<void> {
    for (const r of this.items.filter((i: Item) => i.kind === 'Reminder' && !i.sent && i.due && new Date(i.due).getTime() <= Date.now())) {
      const task = this.items.find((i: Item) => i.id === r.parent);
      if (task?.status === '已完成') continue;
      await notificationManager.publish({ id: Math.floor(r.at % 2000000000), content: { notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT, normal: { title: 'CompetitionHub 截止提醒', text: task?.name || r.name, additionalText: task?.due || '' } } });
      r.sent = true; await this.repo.save([r], '发送本地提醒');
    }
    await this.reload();
  }
  private list(): Item[] {
    const kind = this.kinds[this.page];
    return this.items.filter((i: Item) => {
      if (i.kind !== kind || !(i.name + i.note + i.owner).toLowerCase().includes(this.query.toLowerCase())) return false;
      if (this.filter !== '全部' && i.status !== this.filter) return false;
      if (['Track', 'TeamMember'].includes(kind)) return !this.competition || i.parent === this.competition;
      if (['EligibilityRule', 'MaterialRequirement'].includes(kind)) return !this.track || i.parent === this.track;
      if (['MaterialFile', 'FileVersion'].includes(kind)) return this.materials().some((m: Item) => m.id === i.parent);
      if (kind === 'Task') return !this.competition || i.parent === this.competition || i.parent === this.track || this.materials().some((m: Item) => m.id === i.parent);
      return true;
    }).sort((a: Item, b: Item) => this.descending ? b.at - a.at : a.name.localeCompare(b.name));
  }
  private materials(): Item[] { return this.items.filter((i: Item) => i.kind === 'MaterialRequirement' && (!this.track || i.parent === this.track)); }
  private chosen(): Item | undefined { return this.items.find((i: Item) => i.id === this.selected); }
  private parentName(item: Item): string { return this.items.find((i: Item) => i.id === item.parent)?.name || '独立任务'; }
  private states(kind: string): string[] {
    if (kind === 'EligibilityRule') return ['待确认', '符合', '不符合'];
    if (kind === 'Competition') return ['未开始', '准备中', '已提交', '已归档'];
    return ['未开始', '准备中', '待审核', '已完成', '需修改'];
  }
  private newItem(kind: string): void {
    const item = new Item(); item.id = uid(); item.kind = kind;
    item.parent = ['Track', 'TeamMember', 'Task'].includes(kind) ? this.competition : this.track;
    item.status = this.states(kind)[0];
    this.draft = item; this.editing = true;
  }
  private edit(item: Item): void { this.draft = JSON.parse(JSON.stringify(item)) as Item; this.editing = true; }
  private async saveDraft(): Promise<void> {
    const d = this.draft;
    if (!d.name.trim()) throw new Error('名称不能为空');
    const old = this.items.find((i: Item) => i.id === d.id);
    if (d.kind === 'MaterialFile' && old && extension(d.name) !== extension(old.name)) throw new Error('重命名不能改变文件扩展名；本应用不伪造格式转换');
    if (d.kind === 'Reminder') d.sent = false;
    if (d.due && !Number.isFinite(new Date(d.due).getTime())) throw new Error('截止日期格式无效');
    if (d.start && (!Number.isFinite(new Date(d.start).getTime()) || (d.due && new Date(d.start).getTime() > new Date(d.due).getTime()))) throw new Error('开始日期无效或晚于截止日期');
    if (d.kind !== 'Competition' && !d.parent) throw new Error('请先选择所属竞赛和赛道');
    if (!Number.isFinite(d.maxMB) || d.maxMB <= 0) throw new Error('大小上限必须为正数');
    const writes: Item[] = [d];
    if (d.kind === 'Track' && !this.items.some((i: Item) => i.id === d.id)) {
      ['报名表', '项目申报书', '参赛承诺书', '团队成员信息表', '演示视频', '答辩 PPT', '项目源代码'].forEach((name: string, n: number) => {
        const m = new Item(); m.kind = 'MaterialRequirement'; m.id = uid(); m.parent = d.id; m.name = name; m.required = n < 4;
        m.formats = n === 4 ? 'mp4' : n === 5 ? 'pptx,pdf' : n === 6 ? 'zip' : 'pdf,docx';
        m.maxMB = n === 4 ? 500 : 50; m.due = d.due; writes.push(m);
      });
    }
    d.at = Date.now(); await this.repo.save(writes, '保存条目');
    if (d.kind === 'Competition') { this.competition = d.id; this.track = ''; }
    if (d.kind === 'Track') this.track = d.id;
    this.editing = false; this.selected = d.id; await this.reload(); this.message = '已保存';
  }
  private async importVersion(m: Item): Promise<void> {
    const count = this.items.filter((i: Item) => i.kind === 'FileVersion' && i.parent === m.id).length;
    const result = await this.files!.importFile(JSON.parse(JSON.stringify(m)) as Item, `V${count + 1}.0`, m.owner, '系统文件选择器导入');
    if (!result.length) { this.message = '已取消导入'; return; }
    try { await this.repo.save(result, '导入文件并创建版本'); }
    catch (e) { this.files!.discard(result); throw new Error((e as Error).message || JSON.stringify(e)); }
    await this.reload(); this.message = '文件已复制到私有资料库，历史文件保持独立';
  }
  private async setVersion(v: Item, final: boolean): Promise<void> {
    const m = this.items.find((i: Item) => i.id === v.parent);
    if (!m) throw new Error('材料已不存在');
    if (final) { m.final = v.id; v.status = '已完成'; } else m.current = v.id;
    await this.repo.save([m, v], final ? '指定最终版（不代替材料审核）' : '切换当前版本');
    await this.reload(); this.message = final ? '已指定最终版本；请在材料清单中完成审核' : '已恢复当前版本，历史记录完整保留';
  }
  private async previewFile(item: Item): Promise<void> {
    const f = item.kind === 'FileVersion' ? this.items.find((i: Item) => i.id === item.source) : item;
    if (!f) throw new Error('关联文件不存在');
    const ext = extension(f.name);
    if (['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'].includes(ext)) { this.preview = f.path; this.previewType = 'image'; }
    else if (ext === 'pdf') {
      // PC emulator PDF exports can be incomplete: do not link them at startup.
      if (await hasPdfPreview()) {
        await this.getUIContext().getRouter().pushUrl({ url: 'pages/PdfPreview', params: { path: f.path } as PdfPreviewParams });
      } else {
        await this.files!.open(f); this.message = '当前环境不提供应用内 PDF 预览，已请求系统应用打开';
      }
    }
    else { await this.files!.open(f); this.message = '已请求系统应用打开文件'; }
  }
  private async check(): Promise<void> {
    const t = this.items.find((i: Item) => i.id === this.track);
    if (!t) throw new Error('请先创建并选择赛道');
    this.findings = verify(t, this.items, await this.files!.checks(this.items), Date.now());
    const report = new Item(); report.kind = 'VerificationResult'; report.id = uid(); report.parent = t.id;
    report.name = `${t.name} · ${new Date().toLocaleString()}`;
    report.status = this.findings.some((f: Finding) => f.level === '未通过') ? '未通过' : this.findings.some((f: Finding) => f.level === '警告') ? '警告' : '通过';
    report.note = this.reportText(); await this.repo.save([report], '执行提交核验'); await this.reload(); this.message = `核验完成：${report.status}`;
  }
  private reportText(): string { return `创新竞赛报名资料台核验报告\n时间：${new Date().toISOString()}\n${this.findings.map((f: Finding) => `[${f.level}][${f.human ? '人工确认' : '自动核验'}] ${f.target}：${f.message}`).join('\n')}`; }
  private exportPackage(): void {
    this.run(async () => {
      await this.check();
      if (this.findings.some((f: Finding) => f.level === '未通过')) throw new Error('核验未通过，请修复明确缺失后再导出');
      this.getUIContext().showAlertDialog({ title: '确认最终版本与人工事项', message: this.reportText(), primaryButton: { value: '返回检查', action: () => {} }, secondaryButton: { value: '已确认，导出 ZIP', action: () => {
        this.run(async () => { await this.check(); if (this.findings.some((f: Finding) => f.level === '未通过')) throw new Error('数据已变化，请重新核验'); this.message = await this.files!.package(this.items.find((i: Item) => i.id === this.track)!, this.items, this.reportText()) ? '提交材料已导出，原件保持完整' : '已取消导出'; });
      } } });
    });
  }
  private remove(item: Item): void {
    this.getUIContext().showAlertDialog({ title: '删除条目', message: `删除“${item.name}”？存在子项或受保护历史时会阻止删除。`, primaryButton: { value: '取消', action: () => {} }, secondaryButton: { value: '删除', action: () => { this.run(async () => { await this.repo.remove(item); this.selected = ''; if (this.competition === item.id) { this.competition = ''; this.track = ''; } if (this.track === item.id) this.track = ''; await this.reload(); this.message = '已删除'; }); } } });
  }

  @Builder
  field(label: string, value: string, change: (v: string) => void) {
    Column({ space: 6 }) { Text(label).fontSize(12).fontColor($r('app.color.hub_secondary')); TextInput({ text: value }).onChange(change).height(38).backgroundColor($r('app.color.hub_canvas')) }.alignItems(HorizontalAlign.Start).width('100%')
  }
  @Builder
  stat(label: string, value: string, note: string) {
    Column({ space: 12 }) { Text(label).fontSize(13).fontColor('#6C7890'); Text(value).fontSize(30).fontWeight(FontWeight.Bold).fontColor('#284FBE'); Text(note).fontSize(12).fontColor($r('app.color.hub_subtle')) }.alignItems(HorizontalAlign.Start).padding(22).backgroundColor($r('app.color.hub_surface')).borderRadius(18).layoutWeight(1)
  }
  @Builder
  dashboard() {
    Column({ space: 22 }) {
      Text('让每一份准备，都有据可查。').fontSize(28).fontWeight(FontWeight.Bold).alignSelf(ItemAlign.Start)
      Text('从报名规则到最终版本，在本机完成竞赛准备。').fontSize(14).fontColor($r('app.color.hub_secondary')).alignSelf(ItemAlign.Start)
      Row({ space: 16 }) {
        this.stat('全部竞赛', `${this.items.filter((i: Item) => i.kind === 'Competition').length}`, '来自本地数据库')
        this.stat('正在准备', `${this.items.filter((i: Item) => i.kind === 'Competition' && i.status === '准备中').length}`, '按报名状态统计')
        this.stat('七天内截止', `${this.items.filter((i: Item) => i.kind === 'Competition' && i.status !== '已归档' && i.status !== '已提交' && new Date(i.due).getTime() >= Date.now() && new Date(i.due).getTime() <= Date.now() + 7 * 86400000).length}`, '请优先检查材料')
      }.width('100%')
      Column({ space: 14 }) {
        Text('当前赛道 · 准备进度').fontSize(18).fontWeight(FontWeight.Medium)
        Text(`全部材料 ${percent(this.materials())}%  /  必填材料 ${percent(this.materials().filter((i: Item) => i.required))}%`).fontColor('#284FBE')
        Progress({ value: percent(this.materials()), total: 100, type: ProgressType.Linear }).width('100%').color('#4671F5')
        Text(`资格确认 ${this.items.filter((i: Item) => i.kind === 'EligibilityRule' && i.parent === this.track && i.status === '符合').length} / ${this.items.filter((i: Item) => i.kind === 'EligibilityRule' && i.parent === this.track).length}；审核完成 ${this.materials().filter((i: Item) => i.status === '已完成').length} / ${this.materials().length}；最终版 ${this.materials().filter((i: Item) => !!i.final).length} / ${this.materials().length}`).fontSize(13)
        Text('准备度按材料、审核、资格和时间风险分别解释；缺少规则时不能视为准备完成。').fontSize(12).fontColor($r('app.color.hub_secondary'))
        if (this.items.find((i: Item) => i.id === this.track)) {
          Text(`综合准备度 ${readiness(this.items.find((i: Item) => i.id === this.track)!, this.items, Date.now()).score} / 100`).fontSize(20).fontWeight(FontWeight.Bold)
          ForEach(readiness(this.items.find((i: Item) => i.id === this.track)!, this.items, Date.now()).reasons, (reason: string) => { Text(reason).fontSize(12).fontColor($r('app.color.hub_secondary')) })
        }
      }.alignItems(HorizontalAlign.Start).padding(24).backgroundColor($r('app.color.hub_surface')).borderRadius(18).width('100%')
      Row({ space: 12 }) { Button('新建竞赛').onClick(() => this.newItem('Competition')); Button('管理材料').onClick(() => this.page = 4); Button('创建任务').onClick(() => this.newItem('Task')); Button('提交核验').onClick(() => this.page = 7) }
      Text('待办与截止时间轴').fontSize(18).alignSelf(ItemAlign.Start)
      ForEach(this.items.filter((i: Item) => i.kind === 'Task' && i.status !== '已完成').sort((a: Item, b: Item) => a.due.localeCompare(b.due)).slice(0, 8), (item: Item) => {
        Row() { Text(item.due || '未设日期').width(160).fontColor('#4671F5'); Text(item.name).layoutWeight(1); Text(item.priority); Button('处理').onClick(() => { this.page = 8; this.selected = item.id; }) }.padding(14).backgroundColor($r('app.color.hub_surface')).borderRadius(12).width('100%')
      }, (item: Item) => item.id)
      Text('最近编辑的材料与文件').fontSize(18).alignSelf(ItemAlign.Start)
      ForEach(this.items.filter((i: Item) => ['MaterialRequirement', 'MaterialFile'].includes(i.kind)).slice(0, 6), (item: Item) => { Text(`${item.name}  ·  ${this.parentName(item)}  ·  ${item.status}`).fontSize(13).alignSelf(ItemAlign.Start).onClick(() => { this.page = item.kind === 'MaterialFile' ? 5 : 4; this.selected = item.id; }) }, (item: Item) => item.id)
      if (this.items.length === 0) { Text('还没有竞赛。新建一场竞赛，再创建赛道，系统将为你建立可编辑的材料清单。').fontColor($r('app.color.hub_secondary')) }
    }.width('100%')
  }
  @Builder
  editor() {
    Column({ space: 14 }) {
      Text(`编辑 · ${this.draft.kind === 'TeamMember' ? '团队成员' : this.navigation[this.page]}`).fontSize(20)
      this.field('名称', this.draft.name, (v: string) => { this.draft.name = v; })
      if (this.draft.kind !== 'Competition') { Text(`所属：${this.parentName(this.draft)}`).fontSize(12).fontColor($r('app.color.hub_secondary')) }
      Select(this.states(this.draft.kind).map((s: string): SelectOption => ({ value: s }))).value(this.draft.status).onSelect((n: number) => { this.draft.status = this.states(this.draft.kind)[n]; })
      this.field('负责人 / 修改人 / 团队成员专业', this.draft.owner, (v: string) => { this.draft.owner = v; })
      this.field('截止时间（例：2026-11-01T18:00:00）', this.draft.due, (v: string) => { this.draft.due = v; })
      if (this.draft.kind === 'Competition') {
        this.field('主办方', this.draft.organizer, (v: string) => { this.draft.organizer = v; })
        this.field('级别', this.draft.level, (v: string) => { this.draft.level = v; })
        this.field('类别', this.draft.category, (v: string) => { this.draft.category = v; })
        this.field('报名开始时间', this.draft.start, (v: string) => { this.draft.start = v; })
        this.field('官方通知来源', this.draft.source, (v: string) => { this.draft.source = v; })
        this.field('报名网址', this.draft.url, (v: string) => { this.draft.url = v; })
      }
      if (this.draft.kind === 'EligibilityRule') {
        this.field('规则来源', this.draft.source, (v: string) => { this.draft.source = v; })
        this.field('证明材料条目 ID（在材料详情查看）', this.draft.current, (v: string) => { this.draft.current = v; })
      }
      if (this.draft.kind === 'MaterialRequirement') {
        Row({ space: 12 }) { Text('必填材料'); Toggle({ type: ToggleType.Switch, isOn: this.draft.required }).onChange((v: boolean) => { this.draft.required = v; }) }
        this.field('允许格式（逗号分隔，留空表示不限）', this.draft.formats, (v: string) => { this.draft.formats = v; })
        this.field('大小限制 MB', `${this.draft.maxMB}`, (v: string) => { this.draft.maxMB = Number(v); })
      }
      if (this.draft.kind === 'Task') { Select([{ value: '普通' }, { value: '重要' }, { value: '紧急' }]).value(this.draft.priority).onSelect((n: number) => { this.draft.priority = ['普通', '重要', '紧急'][n]; }) }
      this.field('备注 / 要求 / 修改说明', this.draft.note, (v: string) => { this.draft.note = v; })
      Row({ space: 12 }) { Button('保存').enabled(!this.busy).onClick(() => this.run(async () => this.saveDraft())); Button('取消').onClick(() => this.editing = false) }
    }.alignItems(HorizontalAlign.Start).width('100%').padding(22).backgroundColor($r('app.color.hub_surface')).borderRadius(16)
  }
  @Builder
  details(item: Item) {
    Column({ space: 14 }) {
      Text(item.name).fontSize(21).fontWeight(FontWeight.Bold)
      Text(`${this.parentName(item)} · ${item.status}`).fontSize(13).fontColor($r('app.color.hub_secondary'))
      Text(`条目 ID：${item.id}`).fontSize(11).fontColor($r('app.color.hub_secondary')).copyOption(CopyOptions.InApp)
      Text(`负责人：${item.owner || '未分配'}\n截止：${item.due || '未设置'}\n${item.note || '暂无备注'}`).fontSize(13)
      if (item.kind === 'MaterialRequirement') {
        Text(`${item.required ? '必填' : '选填'} · ${item.formats || '不限格式'} · ${item.maxMB} MB`).fontSize(13)
        Text(`当前版：${this.items.find((i: Item) => i.id === item.current)?.name || '未指定'}\n最终版：${this.items.find((i: Item) => i.id === item.final)?.name || '未指定'}`).fontSize(13)
        Button('导入文件 / 新建版本').onClick(() => this.run(async () => this.importVersion(item)))
        ForEach(this.items.filter((i: Item) => i.kind === 'FileVersion' && i.parent === item.id), (v: Item) => {
          Column({ space: 8 }) { Text(`${v.name} · ${v.owner || '未署名'} · ${v.status}`).fontSize(13); Text(new Date(v.at).toLocaleString()).fontSize(11); Row({ space: 8 }) { Button('查看').fontSize(12).onClick(() => this.run(async () => this.previewFile(v))); Button('恢复').fontSize(12).onClick(() => this.run(async () => this.setVersion(v, false))); Button('最终版').fontSize(12).onClick(() => this.run(async () => this.setVersion(v, true))) } }.padding(12).backgroundColor($r('app.color.hub_canvas')).borderRadius(10)
        }, (v: Item) => v.id)
      }
      if (item.kind === 'FileVersion') {
        Text(`版本文件：${this.items.find((i: Item) => i.id === item.source)?.name || '缺失'}\n时间：${new Date(item.at).toLocaleString()}\n大小：${this.items.find((i: Item) => i.id === item.source)?.bytes || 0} 字节`).fontSize(12)
        Button('恢复为当前版本').onClick(() => this.run(async () => this.setVersion(item, false)))
        Button('指定为最终版本').onClick(() => this.run(async () => this.setVersion(item, true)))
        Text('在材料详情中可对比每一版的文件名、大小、时间和修改人。恢复操作仅改变当前指针。').fontSize(12)
      }
      if (item.kind === 'MaterialFile') {
        Text(`大小：${item.bytes} 字节\n修改时间：${new Date(item.modified * 1000).toLocaleString()}\nSHA-256：${item.hash}`).fontSize(12).copyOption(CopyOptions.InApp)
        Button('检查存在性与完整性').onClick(() => this.run(async () => { const checks = await this.files!.checks([item]); this.message = checks[0].exists && checks[0].intact ? '文件存在且 SHA-256 一致' : '文件丢失、无法访问或已被修改'; }))
        Button('导出该文件').onClick(() => this.run(async () => { this.message = await this.files!.saveFile(item.path, item.name) ? '文件已导出' : '已取消'; }))
      }
      if (['MaterialFile', 'FileVersion'].includes(item.kind)) { Button('预览 / 系统打开').onClick(() => this.run(async () => this.previewFile(item))) }
      if (item.kind === 'EligibilityRule') { Text(`规则来源：${item.source || '未填写'}\n证明：${this.items.find((i: Item) => i.id === item.current)?.name || '未关联'}`).fontSize(12) }
      if (item.kind === 'Competition') {
        Text(`主办方：${item.organizer}\n${item.level} · ${item.category}\n通知：${item.source}\n报名：${item.url}`).fontSize(12).copyOption(CopyOptions.InApp)
        Button('添加团队成员').onClick(() => this.newItem('TeamMember'))
        ForEach(this.items.filter((i: Item) => i.kind === 'TeamMember' && i.parent === item.id), (m: Item) => { Row() { Text(`${m.name} · ${m.owner}`).layoutWeight(1); Button('编辑').onClick(() => this.edit(m)); Button('删除').onClick(() => this.remove(m)) } }, (m: Item) => m.id)
        Button('归档竞赛').onClick(() => this.run(async () => { item.status = '已归档'; await this.repo.save([item], '归档竞赛'); await this.reload(); }))
      }
      if (item.kind === 'Task') {
        Button('设置截止时提醒').onClick(() => this.run(async () => {
          if (!item.due) throw new Error('请先设置任务截止时间');
          await notificationManager.requestEnableNotification(this.context!);
          const r = this.items.find((i: Item) => i.kind === 'Reminder' && i.parent === item.id) || new Item(); r.kind = 'Reminder'; if (!r.id) r.id = uid(); r.parent = item.id; r.name = item.name; r.due = item.due; r.sent = false;
          await this.repo.save([r], '设置提醒'); await this.reload(); this.message = '提醒已持久化；应用运行时及重新打开后检查到期提醒';
        }))
        ForEach(this.items.filter((i: Item) => i.kind === 'Reminder' && i.parent === item.id), (r: Item) => { Row() { Text(`提醒：${r.due}`).fontSize(12).layoutWeight(1); Button('修改时间').onClick(() => this.edit(r)); Button('取消').onClick(() => this.remove(r)) } }, (r: Item) => r.id)
      }
      if (item.kind !== 'VerificationResult') { Row({ space: 8 }) { Button('编辑').onClick(() => this.edit(item)); if (!['FileVersion', 'MaterialFile'].includes(item.kind)) { Button('删除').fontColor('#C55454').onClick(() => this.remove(item)) } } }
      Text('最近修改记录').fontSize(14)
      ForEach(this.items.filter((i: Item) => i.kind === 'OperationLog' && i.note.includes(item.id)).slice(0, 10), (log: Item) => { Text(`${new Date(log.at).toLocaleString()} · ${log.name}`).fontSize(11).fontColor($r('app.color.hub_secondary')) }, (log: Item) => log.id)
    }.alignItems(HorizontalAlign.Start).padding(22).width('100%').backgroundColor($r('app.color.hub_surface')).borderRadius(16)
  }
  @Builder
  rows() {
    Column({ space: 10 }) {
      if (this.list().length === 0) { Column({ space: 16 }) { Text('这里还没有记录').fontSize(23); Text('通过右上角新建开始；材料文件请从材料详情导入。').fontColor($r('app.color.hub_secondary')) }.padding(50).width('100%').backgroundColor($r('app.color.hub_surface')).borderRadius(16) }
      ForEach(this.list(), (item: Item) => {
        Row({ space: 14 }) {
          Column({ space: 8 }) { Text(item.name).fontSize(16).fontWeight(FontWeight.Medium); Text(`${this.parentName(item)} · ${item.owner || '未分配'}${item.kind === 'MaterialFile' ? ' · ' + item.bytes + ' 字节' : ''}`).fontSize(12).fontColor($r('app.color.hub_secondary')) }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Text(item.status).fontSize(12).fontColor(item.status === '已完成' || item.status === '符合' ? '#16896E' : '#5872AE').padding(8).backgroundColor($r('app.color.hub_tag')).borderRadius(8)
          if (!this.grid) { Text(item.due || new Date(item.at).toLocaleDateString()).fontSize(12).width(155).fontColor($r('app.color.hub_secondary')) }
          Button('详情').fontSize(12).onClick(() => this.selected = item.id)
        }.width('100%').padding(this.grid ? 28 : 18).backgroundColor($r('app.color.hub_surface')).borderRadius(14).border({ width: this.selected === item.id ? 1 : 0, color: '#4671F5' }).onClick(() => this.selected = item.id)
      }, (item: Item) => item.id)
    }.width('100%')
  }
  @Builder
  fileGrid() {
    Grid() {
      ForEach(this.list(), (item: Item) => {
        GridItem() {
          Column({ space: 12 }) {
            Text(extension(item.name).toUpperCase() || '文件').fontSize(13).fontColor('#4671F5')
            Text(item.name).fontSize(16).fontWeight(FontWeight.Medium).maxLines(2)
            Text(`${item.bytes} 字节 · ${this.parentName(item)}`).fontSize(12).fontColor($r('app.color.hub_secondary'))
            Button('详情').onClick(() => this.selected = item.id)
          }.padding(18).width('100%').height('100%').backgroundColor($r('app.color.hub_surface')).borderRadius(16)
        }
      }, (item: Item) => item.id)
    }.columnsTemplate('1fr 1fr').columnsGap(14).rowsGap(14).height(Math.max(220, Math.ceil(this.list().length / 2) * 210))
  }
  @Builder
  verifyPanel() {
    Column({ space: 16 }) {
      Text('提交之前，把不确定变得清楚。').fontSize(26).fontWeight(FontWeight.Bold)
      Text('核验文件、版本、材料审核与资格状态。真实性与签章始终由你确认。').fontColor($r('app.color.hub_secondary')).fontSize(13)
      Row({ space: 12 }) { Button('执行核验').onClick(() => this.run(async () => this.check())); Button('导出最终材料 ZIP').onClick(() => this.exportPackage()); Button('保存核验报告').onClick(() => this.run(async () => { await this.check(); const p = `${this.context!.cacheDir}/report.txt`; this.files!.writeText(p, this.reportText()); this.message = await this.files!.saveFile(p, '核验报告.txt') ? '报告已导出' : '已取消'; })) }
      ForEach(this.findings, (f: Finding) => { Row({ space: 14 }) { Text(f.level).fontColor(f.level === '未通过' ? '#C55454' : f.level === '通过' ? '#16896E' : '#A6771B').width(60); Column({ space: 5 }) { Text(f.target).fontWeight(FontWeight.Medium); Text(`${f.human ? '人工确认' : '自动核验'} · ${f.message}`).fontSize(13).fontColor($r('app.color.hub_secondary')) }.alignItems(HorizontalAlign.Start).layoutWeight(1) }.width('100%').padding(18).backgroundColor($r('app.color.hub_surface')).borderRadius(12) })
      Text('历史核验报告').fontSize(18)
      ForEach(this.items.filter((i: Item) => i.kind === 'VerificationResult' && i.parent === this.track).slice(0, 15), (i: Item) => { Text(`${i.name} · ${i.status}`).fontSize(13).onClick(() => this.getUIContext().showAlertDialog({ title: i.name, message: i.note, confirm: { value: '关闭', action: () => {} } })) }, (i: Item) => i.id)
    }.alignItems(HorizontalAlign.Start).width('100%')
  }
  private days(): number[] { const out: number[] = []; for (let d = 1; d <= new Date(this.year, this.month + 1, 0).getDate(); d++) out.push(d); return out; }
  private dayTasks(day: number): Item[] { return this.list().filter((i: Item) => { const d = new Date(i.due); return d.getFullYear() === this.year && d.getMonth() === this.month && d.getDate() === day; }); }
  @Builder
  calendarPanel() {
    Column({ space: 16 }) {
      Row({ space: 12 }) { Button('上月').onClick(() => { if (this.month === 0) { this.month = 11; this.year--; } else this.month--; }); Text(`${this.year} 年 ${this.month + 1} 月`).fontSize(22); Button('下月').onClick(() => { if (this.month === 11) { this.month = 0; this.year++; } else this.month++; }) }
      Grid() {
        ForEach(this.days(), (day: number) => {
          GridItem() { Column({ space: 6 }) { Text(`${day} 日`).fontSize(14); ForEach(this.dayTasks(day), (t: Item) => { Text(`${t.name} · ${t.priority}`).fontSize(11).fontColor('#4671F5').maxLines(2).onClick(() => this.selected = t.id) }, (t: Item) => t.id) }.alignItems(HorizontalAlign.Start).padding(12).width('100%').height('100%').backgroundColor($r('app.color.hub_surface')).borderRadius(12) }
        }, (day: number) => `${day}`)
      }.columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr').columnsGap(8).rowsGap(8).height(600)
    }.width('100%')
  }
  @Builder
  settings() {
    Column({ space: 20 }) {
      Text('本机资料与偏好').fontSize(26).fontWeight(FontWeight.Bold)
      Text('应用不连接云端。导入文件复制到沙箱，历史版本禁止直接删除。').fontSize(14)
      Row({ space: 12 }) { Button('跟随系统').onClick(() => this.context!.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)); Button('浅色主题').onClick(() => this.context!.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT)); Button('深色主题').onClick(() => this.context!.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK)) }
      Button('导出数据库与全部文件备份').onClick(() => this.run(async () => { const path = `${this.context!.cacheDir}/competitionhub-backup.db`; await this.repo.backup(path); this.message = await this.files!.backup(path) ? '完整备份已导出，请妥善保存' : '已取消'; }))
      Button('从完整备份恢复').onClick(() => this.getUIContext().showAlertDialog({ title: '恢复数据库', message: '恢复将替换当前数据库。现有托管文件保留，冲突文件不会覆盖。请先导出当前备份。', primaryButton: { value: '取消', action: () => {} }, secondaryButton: { value: '选择备份', action: () => { this.run(async () => {
        const dir = await this.files!.chooseBackup(); if (!dir) { this.message = '已取消恢复'; return; }
        const rollback = `${this.context!.cacheDir}/before-restore.db`; await this.repo.backup(rollback);
        try {
          await this.repo.restore(`${dir}/competitionhub.db`);
          const all = await this.repo.all();
          if (all.some((i: Item) => !TABLES.includes(i.kind) || !i.id || !i.name)) throw new Error('备份记录结构不符合要求');
          const rebased = await this.files!.restoreFiles(dir, all); await this.repo.save(rebased, '恢复完整备份');
          this.competition = ''; this.track = ''; this.selected = ''; await this.reload(); this.message = '数据库和材料已恢复';
        } catch (e) { await this.repo.restore(rollback); await this.reload(); throw new Error((e as Error).message || JSON.stringify(e)); }
      }); } } }))
      Text('提醒设置可跨启动保留；到期通知仅在应用运行和重新打开时触发，未实现关闭应用后的定时唤醒。').fontSize(13).fontColor($r('app.color.hub_secondary'))
      Text('快捷键：Ctrl+N 新建，Ctrl+F 聚焦搜索，Esc 关闭编辑。文件通过系统选择器导入；拖拽和多窗口未启用。').fontSize(13).fontColor($r('app.color.hub_secondary'))
      Text('操作记录').fontSize(18)
      ForEach(this.items.filter((i: Item) => i.kind === 'OperationLog').slice(0, 30), (log: Item) => { Text(`${new Date(log.at).toLocaleString()} · ${log.name}`).fontSize(12) }, (log: Item) => log.id)
    }.alignItems(HorizontalAlign.Start).padding(24).backgroundColor($r('app.color.hub_surface')).borderRadius(18).width('100%')
  }

  build() {
    Row() {
      Column({ space: 9 }) {
        Row({ space: 10 }) { Text('C').fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.hub_surface')).padding(12).backgroundColor('#4671F5').borderRadius(14); Column({ space: 4 }) { Text('CompetitionHub').fontSize(16).fontWeight(FontWeight.Bold); Text('创新竞赛报名资料台').fontSize(11).fontColor($r('app.color.hub_secondary')) }.alignItems(HorizontalAlign.Start) }.margin({ bottom: 24, top: 18 })
        ForEach(this.navigation, (title: string, index: number) => {
          Row({ space: 12 }) { Text(`${index + 1}`.padStart(2, '0')).fontSize(12).fontColor($r('app.color.hub_subtle')); Text(title).fontSize(14).fontColor(this.page === index ? '#284FBE' : $r('app.color.hub_nav')) }.width('100%').padding(14).borderRadius(12).backgroundColor(this.page === index ? $r('app.color.hub_selected') : Color.Transparent).onClick(() => { this.page = index; this.editing = false; this.selected = ''; this.query = ''; this.filter = '全部'; })
        }, (title: string) => title)
        Blank()
        Text('本地离线 · 版本可追溯').fontSize(11).fontColor($r('app.color.hub_subtle')).margin({ bottom: 20 })
      }.width(this.viewport < 1000 ? 180 : 226).height('100%').padding({ left: 16, right: 16 }).backgroundColor($r('app.color.hub_surface'))
      Column({ space: 0 }) {
        Row({ space: 16 }) {
          Text(this.navigation[this.page]).fontSize(20).fontWeight(FontWeight.Bold)
          Blank()
          TextInput({ placeholder: '搜索名称、负责人、备注', text: this.query }).id('search').width(this.viewport < 1000 ? 160 : 260).height(38).onChange((v: string) => this.query = v)
          if ([1, 2, 3, 4, 8].includes(this.page)) { Button('+ 新建').onClick(() => this.newItem(this.kinds[this.page])).keyboardShortcut('n', [ModifierKey.CTRL]) }
        }.height(78).width('100%').padding({ left: 28, right: 28 }).backgroundColor($r('app.color.hub_surface'))
        Scroll() {
        Row({ space: 12 }) {
          Text('竞赛').fontSize(12)
          Select(this.items.filter((i: Item) => i.kind === 'Competition').map((i: Item): SelectOption => ({ value: i.name }))).value(this.items.find((i: Item) => i.id === this.competition)?.name || '请选择竞赛').onSelect((n: number) => { this.competition = this.items.filter((i: Item) => i.kind === 'Competition')[n].id; this.track = this.items.find((i: Item) => i.kind === 'Track' && i.parent === this.competition)?.id || ''; this.selected = ''; this.findings = []; }).width(220)
          Text('赛道').fontSize(12)
          Select(this.items.filter((i: Item) => i.kind === 'Track' && i.parent === this.competition).map((i: Item): SelectOption => ({ value: i.name }))).value(this.items.find((i: Item) => i.id === this.track)?.name || '请选择赛道').onSelect((n: number) => { this.track = this.items.filter((i: Item) => i.kind === 'Track' && i.parent === this.competition)[n].id; this.selected = ''; this.findings = []; }).width(220)
          Blank()
          if (this.page > 0 && this.page < 9 && this.page !== 7) { Select(['全部'].concat(this.states(this.kinds[this.page])).map((s: string): SelectOption => ({ value: s }))).value(this.filter).onSelect((n: number) => this.filter = ['全部'].concat(this.states(this.kinds[this.page]))[n]); Button(this.descending ? '最近优先' : '名称排序').fontSize(12).onClick(() => this.descending = !this.descending) }
        }.padding(16).width(this.viewport < 1400 ? 1100 : '100%')
        }.scrollable(ScrollDirection.Horizontal).width('100%')
        if (this.page === 5) { Row({ space: 12 }) { Button(this.grid ? '紧凑列表' : '卡片视图').onClick(() => this.grid = !this.grid); Text('从材料详情导入文件；重命名只改变展示名称，托管文件保持不可变。').fontSize(12) }.padding(12) }
        if (this.page === 8) { Button(this.calendar ? '任务列表' : '月历视图').onClick(() => this.calendar = !this.calendar) }
        Row({ space: 18 }) {
          Scroll() {
            Column({ space: 16 }) {
              if (this.preview) { Row() { Text('图片预览').layoutWeight(1); Button('关闭').onClick(() => this.preview = '') }; Image(this.preview).objectFit(ImageFit.Contain).height(600).width('100%') }
              else if (this.editing) { this.editor() }
              else if (this.page === 0) { this.dashboard() }
              else if (this.page === 7) { this.verifyPanel() }
              else if (this.page === 9) { this.settings() }
              else if (this.chosen() && this.viewport < 1200) { Button('返回列表').onClick(() => this.selected = ''); this.details(this.chosen()!) }
              else if (this.page === 8 && this.calendar) { this.calendarPanel() }
              else if (this.page === 5 && this.grid && this.list().length > 0) { this.fileGrid() }
              else { this.rows() }
            }.width('100%')
          }.layoutWeight(1).height('100%').align(Alignment.Top)
          if (this.chosen() && !this.editing && this.page !== 0 && this.page !== 7 && this.page !== 9 && this.viewport >= 1200) { Scroll() { this.details(this.chosen()!) }.width('35%').height('100%').align(Alignment.Top) }
        }.padding({ left: 26, right: 26, bottom: 20 }).layoutWeight(1).width('100%')
        Row({ space: 10 }) { if (this.busy) { LoadingProgress().width(18).height(18) } Text(this.message).fontSize(12).fontColor($r('app.color.hub_nav')).maxLines(2); Blank(); Text('API 22 · 原生 ArkUI').fontSize(11).fontColor($r('app.color.hub_subtle')) }.height(44).padding({ left: 26, right: 26 }).width('100%')
      }.height('100%').layoutWeight(1).backgroundColor($r('app.color.hub_canvas'))
    }.height('100%').width('100%').onAreaChange((_old: Area, area: Area) => { this.viewport = Number(area.width); }).onKeyEvent((event: KeyEvent) => { if (event.type === KeyType.Down && event.keyCode === 2070) { this.editing = false; this.preview = ''; } else if (event.type === KeyType.Down && event.keyCode === 2022 && event.getModifierKeyState?.(['Ctrl'])) { this.getUIContext().getFocusController().requestFocus('search'); } }).enabled(!this.busy)
  }
}
