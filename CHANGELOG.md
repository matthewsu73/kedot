# 更新记录 / Changelog

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
