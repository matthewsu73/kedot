# 更新记录 / Changelog

## 2.3.0 — 正式版 / Release (2026-10-29)

- 将当前 Mac 2.3 功能作为正式版发行，构建23003；此前Beta记录保留供参考。
- 包含逐集状态、时间戳笔记、学习统计、原生窗口控制和简化导航。
- 去除悬浮窗外圈细边框，放大默认字体；新增80%–140%字体调节、即时生效及偏好保存。
- Promote the current Mac 2.3 features to release, build23003, with per-part completion, notes, statistics and native window controls.
- Remove the outer widget outline, enlarge default text and add persistent 80%–140% font adjustment.
- 保留临时签名和实机覆盖限制；详见发行说明。Ad-hoc signing and documented verification limits remain.

## 2.3.0 Beta 2 — 窗口与导航 / Window and navigation

- 使用系统标题栏拖动、原生关闭/最小化/缩放；关闭悬浮窗仅收起，菜单栏可恢复，退出时保存。
- 统一课程、统计、设置为控制中心三个分区；常用操作扁平化，支持窗口预设、居中和恢复默认。
- 移动/缩放延迟合并保存位置；屏幕变化与离屏位置自动调整。
- Native title-bar movement and window controls; closing hides the widget while synchronization continues. Restore from the menu bar.
- Three control-center sections: courses, statistics and settings; size presets, centering and reset.
- Debounced geometry persistence and display-bound placement recovery. Local beta; GitHub sync requires approval.

## 2.3.0 Beta 1 — 测试版 / Test release

- 逐集完成状态、手动覆盖和恢复自动；95%播放位置自动完成，回看不撤销。
- 纯文本时间戳笔记，可新增/编辑/删除，打开分集并请求时间跳转。
- 今日、7天、累计、90天记录和课程时长统计；支持倍速、去重、跳转排除、跨午夜分摊。
- 旧格式默认迁移、首写备份、测试版标识；当前版本均为测试版，完整版尚无确定计划。
- Per-part completion with persistent manual overrides; automatic position-threshold completion survives rewinding.
- Timestamped plain-text notes with create/edit/delete and part/time links.
- Today/seven-day/all-time totals, 90-day records and course breakdown; playback-rate-aware estimates, deduplication, seek exclusion and local-midnight splitting.
- Legacy schema migration, first-write backup and beta labeling. No date or scope is committed for a possible full version.

## 2.2.1 — SwiftUI 优化 / SwiftUI improvements

### 简体中文

- 标题栏、连接状态、课程列表和搜索区独立观察变化，减少进度同步引起的无关界面更新。
- 已选课程只在课程数据变化时筛选；相同刷新跳过赋值，课程数量只在数量改变时通知。
- 手动编辑滑杆始终使用有限且有界的值；缩短时长会同步调整超出的已看时间，保存仍检查原始输入。编辑中的草稿不会被自动同步覆盖。
- 增加编辑框键盘焦点、图标按钮与选中主题的 VoiceOver 描述；系统“减少透明度”开启时使用实色背景。
- 保留 macOS 14、Apple Silicon、现有主题和数据格式兼容性。无新增扩展权限。

### English

- Isolates header, connection status, selected lessons, and search into separate observation boundaries to reduce unrelated playback-driven updates.
- Caches selection filtering, skips unchanged refresh assignments, and changes the observable course count only when the count changes.
- Keeps slider rendering finite and bounded for invalid drafts; shortening duration trims elapsed time. Saving still validates original input, and incoming sync does not overwrite editing drafts.
- Adds initial keyboard focus, VoiceOver labels and selected-theme traits, and opaque backgrounds when Reduce Transparency is enabled.
- Retains macOS 14, Apple Silicon, theme and data-format compatibility. No added extension permissions.

### 验证 / Validation

Native core checks, observation isolation, unchanged refresh, invalid numeric slider drafts, appearance/scaling checks, four native preview sizes, extension/options tests, and real HTTP integration passed locally. New model checks run in GitHub Actions without requiring screenshot capture.

本次未进行 Instruments 性能测量、电池续航对比、VoiceOver 人工朗读验收或真实 Chrome/B站回归；不提供性能或节电提升百分比。

No Instruments profiling, battery comparison, manual VoiceOver acceptance, or live Chrome/Bilibili regression was performed for this update. No percentage improvement is claimed.
