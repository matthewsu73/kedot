# 课点 / Kedot 2.3.0

2026-10-29 · Mac 正式版 / Mac release · build 23003

## 简体中文

- 逐集完成状态，可手动标记或恢复跟随播放；95%播放位置自动完成，回看保留状态。
- 时间戳笔记支持新增、编辑、删除及打开对应分集与时间。
- 今日、7天、累计与每日学习时长统计，按课程汇总，支持倍速、跳转排除及并行标签去重。
- 原生标题栏移动、四边缩放、关闭收起与菜单栏恢复；课程/统计/设置集中在控制中心。
- 六种主题、跟随系统深浅色，悬浮窗字体80%–140%即时调整并自动记忆。
- 保持 MIT 许可。本次将当前2.3测试版本转为正式发行，不包含Windows安装包。

要求 Apple Silicon、macOS14+、Chrome111+。先正常退出旧程序，再替换应用；更新Chrome扩展并刷新B站标签。数据仍在 `~/.bili_course_tracker`。首次写入2.3新格式时保留已有数据为 `pre-2.3-backup.json`，不覆盖已有备份；不要让旧版覆盖新数据，重要笔记请另行备份。

已知限制：ARM64应用为临时签名，未做Apple公证；没有Intel构建。学习时长为连续播放估算，从2.3开始记录，不代表专注度或完整观看。真实播放器时间跳转、macOS14/15、完整VoiceOver、多显示器/Spaces/全屏及长期功耗尚未完整实机验收。详见 [测试报告](TEST_REPORT_2.3.md)。

## English

- Per-part completion with manual overrides and playback-following mode; the 95% position threshold survives rewinding.
- Timestamped plain-text notes with create, edit, delete and part/time links.
- Today, seven-day, all-time, daily and per-course playback-time estimates, accounting for playback speed, seeks and concurrent tabs.
- Native window movement/resizing, close-to-hide and menu-bar restore; courses, statistics and settings in one control center.
- Six themes, system light/dark mode and a persistent 80%–140% widget font control.
- MIT licensed. This promotes the current 2.3 beta to a Mac release; no Windows installer is included.

Requires Apple Silicon, macOS14+ and Chrome111+. Quit older instances before replacing the app, reload the updated extension and refresh Bilibili tabs. Existing data stays in `~/.bili_course_tracker`. The first 2.3 write retains an existing database as `pre-2.3-backup.json` unless already present. Back up important notes separately and avoid downgrading against the new database.

Known limitations: ad-hoc signed ARM64 app, without Apple notarization or Intel binaries. Statistics are conservative playback estimates starting with 2.3, not proof of attention or full viewing. Live-player timestamp seeking, older macOS machines, complete VoiceOver, physical multi-monitor/Spaces/fullscreen behavior and long-term power use have not been fully verified. See the [validation report](TEST_REPORT_2.3.md).
