# 创新竞赛报名资料台 CompetitionHub

HarmonyOS PC 原生 ArkTS / ArkUI、Stage UIAbility、本地关系型数据库与私有文件资料库。目标 SDK 为用户已有工程的 **HarmonyOS 6.0.2（API 22），设备类型 2in1**。

2026-10-15 已修复用户模拟器的 PDF 模块缺失导致的启动闪退，并在用户现有 MateBook Pro 模拟器上覆盖安装、打开首页和冷启动复查通过。详情见 `docs/闪退修复.md`。

这是核心业务工程交付，包含真实数据库、文件导入、版本选择、规则核验、最终材料 ZIP 导出及完整备份恢复代码。没有预置竞赛、样例文件或伪造统计。当前验证范围和未完成项见 `docs/测试报告.md`，不能把源码交付理解为已完成真机验收。

## 打开与运行

1. 在 DevEco Studio 中 Open 此目录，等待工程同步。安装 HarmonyOS 6.0.2 Release / API 22 SDK 及 2in1 设备支持。
2. 在 File → Project Structure → Signing Configs 为自己的华为开发者账号配置调试签名，选择匹配此应用包名的证书及 Profile。交付工程不含私钥、账号或签名材料。
3. 选择鸿蒙电脑或兼容 2in1 模拟器，运行 `entry`。包名：`com.competitionhub.desktop`。
4. 首次启动为空数据库。创建竞赛 → 创建赛道 → 修改默认材料模板 → 添加资格规则 → 导入真实文件 → 标记最终版与审核状态 → 执行核验 → 导出 ZIP。

命令行构建可使用 `scripts/Build.ps1`。构建生成的 unsigned HAP 必须签名后才能安装到常规设备。原用户工程 `C:\Users\Luwenyu\DevEcoStudioProjects\MyApplication` 未被修改。

## 工程结构

```text
AppScope/                         应用包信息、图标
entry/src/main/ets/
  entryability/EntryAbility.ets    Stage 生命周期入口
  pages/Index.ets                 中文桌面 UI 与操作协调
  model/Domain.ets                领域模型、纯核验规则、准备度分析
  data/Repository.ets             RDB 表、事务、关联校验和操作日志
  services/FileService.ets        文件选择、复制、SHA-256、预览打开、ZIP、备份
entry/src/main/resources/         浅色 / 深色资源与 SVG 图标
tests/                           直接加载业务源码的本地单元测试
docs/                            用户手册、架构、可行性、测试、竞赛演示
scripts/                         本地构建入口
```

## 核心行为

- 竞赛、赛道、资格、材料、任务和团队成员可新增、编辑及受关联保护地删除。竞赛支持归档。搜索名称、负责人和备注；按名称或最近修改排序，按竞赛及赛道隔离查看。
- 创建赛道会生成七项**待编辑的规则模板**，不代表真实竞赛规定。必须按官方通知修改必填性、格式、大小及截止时间。
- 文件导入经系统选择器授权，立即复制至应用 `filesDir/vault`。不扫描用户磁盘、不覆盖原件。重命名不得改变扩展名。
- 一个材料拥有多个独立不可删除的历史版本。恢复仅改变当前版本指针；最终版本指针独立。指定最终版不等同于材料已完成审核。
- 核验检查必填材料、审核、最终版、文件存在性、SHA-256、扩展名、大小、资格状态、版本冲突及任务时间风险。签章、真实性和实际内容格式需人工确认。
- 导出重新核验，并要求用户确认最终版本和人工事项。ZIP 内含最终文件、TSV 清单和核验报告；不转换文件格式。
- 完整备份含 RDB 数据库和全部托管文件。恢复前保留回滚数据库，逐文件校验哈希并重新定位沙箱路径；不覆盖同 ID 不同内容的本地文件。

## 验证

在安装了 DevEco Studio 的 Windows 上运行：

```powershell
node tests/domain.test.cjs
node tests/files.test.cjs
# Node 24（内置 SQLite）
& 'C:\Program Files\nodejs\node.exe' tests/repository.test.cjs
```

测试直接转译项目 `.ets` 业务源码。规则测试是纯业务测试；文件测试以 Node 文件和加密适配器执行，不验证 HarmonyOS 原生权限、数据库运行时或 PDFKit。测试中的 TypeScript 路径可用 `TYPESCRIPT_PATH` 环境变量调整。

## 文档

- [可行性与优先级](docs/可行性与优先级.md)
- [软件架构](docs/软件架构.md)
- [用户手册](docs/用户手册.md)
- [测试报告](docs/测试报告.md)
- [创新点与演示](docs/创新点与演示.md)

本地通知目前采用应用运行期间的到期检查；关闭应用后的系统定时提醒、多窗口和文件拖拽未实现。严禁依赖本版本提醒作为唯一的竞赛截止保障。

