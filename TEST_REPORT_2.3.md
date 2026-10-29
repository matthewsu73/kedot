# 2.3.0 正式版验收 / Release validation

- 同版本字体调节：80%–140%、默认100%；检查范围限制、无效数值回退和新实例读取偏好，最小窗口在80%和140%生成原生预览。 Font-size persistence, safe bounds and 80%/140% native minimum-window previews verified.
- macOS Apple Silicon release build and ad-hoc signature verified; 17 native core groups passed.
- Chrome worker/content/options checks and real loopback HTTP integration passed; restart and delayed persistence passed.
- Native preview smoke checks passed at 282×310, 354×430 and 520×620 in light/dark mode, including hide/restore, reset, compact mode and topmost.
- Window placement checks cover offscreen frames, negative-origin displays, oversized frames and nonfinite coordinates.
- 独立数据实例检查控制中心课程/设置导航、设置布局、关闭当前窗口和正常退出；未使用个人课程数据。
- 标题栏拖动进行了交互尝试，但自动化界面树无法量化拖动距离；没有完成真实多显示器、Spaces/全屏、各边拖动缩放、Dock最小化恢复和长时间功耗验收。屏幕边界逻辑有静态与确定性检查，不能替代这些实机测试。
- 正式发行构建23003；无Apple Developer ID公证或Intel构建。下方Beta记录是历史验收，发行检查另行重跑。

## 正式发行回归 / Release regression (2026-10-29)

17组核心检查、Chrome扩展与配对页、正式应用真实本机HTTP集成、字体偏好/范围及四种尺寸深浅色检查均通过。正式包使用2.3.0/build23003/stable元数据；下方未同步GitHub等描述仅对应历史Beta验收。

Release regression passed all 17 core groups, extension/options checks, real packaged-app HTTP integration, font preference/bounds and native light/dark size previews. Release metadata is 2.3.0/build23003/stable. Statements below about an unpublished beta describe historical checks only.

## Previous feature verification / 先前功能验收

# 课点 2.3.0 Beta 1 测试报告 / Validation

日期：2026-10-29。Apple Silicon Mac，Swift 6.3.3，macOS 14最低部署目标。

## 通过的检查

- 17组原生核心检查，含认证/HTTP边界/迁移/保存/手动保护旧测试，以及新逐集完成持久化、回看保留、手动覆盖/恢复自动、笔记增删改查与重启、非法时间和空文本拒绝。
- 旧格式默认迁移、首次写入备份、无效新字段拒绝且原文件保留。
- 统计测试覆盖重复请求、跳转、超过30秒的断联、手动修改不加时、0.5倍速、跨午夜分摊及并行标签去重。统计是连续播放估算，不是完整观看或专注证明。
- Chrome扩展逻辑和配对页检查通过；扩展worker真实fetch → 原生HTTP → JSON、端口冲突/多实例拒绝/重启/10秒延迟写盘通过。
- 四种尺寸/深浅色原生窗口预览、主题与缩放模型检查通过。新增逐集、笔记列表、笔记编辑、统计界面已原生渲染并人工检查图片。
- 隔离数据上的真实UI操作验证新笔记带入P2/12秒、中文保存和编辑、删除二次确认及取消、完成状态即时更新和退出持久化、空统计页面；数据与用户实际课程隔离。

## 未完成与限制

- 没有验证真实Chrome/B站播放器对 `t=` 的跳转行为；URL构造已检查。Chrome需重新加载2.3扩展并刷新视频页，倍速统计才有完整输入。
- 未做完整VoiceOver人工验收、电池/性能量化、macOS14/15或Intel实机覆盖。ARM64应用仍临时签名，未Developer ID签名或Apple公证。
- 没有补算旧学习时长。暂停/离线/后台冻结、倍速变化或网络抖动可能少计；多标签的时间保守归给先收到的有效更新。自动完成仅由播放位置阈值判断，可手动修正。
- 旧版可能忽略新字段并在保存时丢失笔记/统计，升级前应正常退出旧版并备份，不建议直接降级。
- Windows 0.1.0仍为独立的旧预览，本次未将新增UI移植到Windows。
- 未提交或同步GitHub，没有远端CI结果可声称。

## English

Local validation passed 17 native core groups, including completion persistence/rewind/manual overrides, timestamp-note CRUD and reload, invalid notes, schema migration and backup preservation. Study-time tests cover duplicates, seeks, long gaps, manual edits, half-speed playback, midnight boundaries and concurrent-tab deduplication. Existing extension/options tests and real worker-to-native HTTP integration passed, including restart/port/lock/deferred-write checks.

Native theme/size previews and the new parts, notes, editor and statistics screens were rendered and visually inspected. Isolated UI tests created a P2/12-second note and saved/edited Chinese text without touching user courses.

Live Bilibili timestamp seeking, full VoiceOver, energy/performance comparisons, older macOS/Intel machines, Developer ID signing and notarization remain unverified. This is an ARM64 beta. Statistics begin with 2.3 and are conservative playback estimates; they do not prove attention or full viewing. The Windows preview has not gained these interfaces. No GitHub upload, commit, dispatch or remote CI run was performed.
