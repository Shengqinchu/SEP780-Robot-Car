# Android 仪表盘 UI 调研与取舍

调研日期：2026-09-20，America/Toronto。星数是调研时 GitHub 页面快照，仅用于衡量社区规模，不代表代码质量或项目适配度。

## 候选比较

| 项目 | 快照 | 可借鉴内容 | 本项目取舍 |
| --- | ---: | --- | --- |
| [android/nowinandroid](https://github.com/android/nowinandroid) | 21.8k stars，Apache-2.0 | Material 3 信息层级、有限强调色、响应式和截图测试思路 | 借鉴层级与间距；不为单页控制器迁移 Kotlin/Compose |
| [home-assistant/android](https://github.com/home-assistant/android) | 3.9k stars，Apache-2.0 | 状态优先的设备控制、连接状态与操作区分离 | 借鉴“状态先于命令”和快速动作分组；不复制组件或代码 |
| [anastr/SpeedView](https://github.com/anastr/SpeedView) | 1.4k stars，Apache-2.0 | 仪表盘刻度、当前值与范围端点的视觉词汇 | 用轻量自绘 `View` 实现单个 PWM 表，不引入 Kotlin 和额外运行时依赖 |
| [openhab/openhab-android](https://github.com/openhab/openhab-android) | 647 stars，EPL-2.0 | 原生设备控制、语音入口和面板式状态组织 | 借鉴控制流程；不混入其云端、账户或插件结构 |
| [material-components/material-components-android](https://github.com/material-components/material-components-android) | 17.4k stars，Apache-2.0 | 形状、颜色、控件状态和可访问性基线 | GitHub 已标记 Views 库进入维护模式，因此不新增该依赖；沿用平台控件和项目自有 drawable |

## 最终设计

- 顶部只保留产品名、双语切换和带蓝色状态灯的紧凑蓝牙连接区。
- 主界面固定为一页，无滚动容器。
- 初版中央圆盘和四向键已在 2026-09-21 的赛车遥控重构中被模拟摇杆取代；新界面用独立 110–200 上限滑杆，并在摇杆内显示左右请求值。
- 电池、测距、三路循迹作为三个同级实时指标，不与原始诊断文本混在一起。
- 语音和循迹作为明确命令放在遥控器下方；停止键固定在屏幕底部，始终可触达。
- 使用白、深墨色、青绿色、状态黄和危险红形成有层级的多色系统；卡片圆角不超过 8 dp，不使用渐变和装饰性图形。
- 保留 Java/XML、既有 BLE 协议、租约和故障停车逻辑。自绘圆盘只在触摸结束时提交合法档位，触摸开始先触发停止；方向动作仍由原控制器的按住/松开和语音限时逻辑执行。

## 许可与复用边界

本轮没有复制候选项目的源代码、图片、图标或布局文件，也没有加入新的第三方依赖。上述仓库仅作为交互模式与视觉层级参考，因此 `THIRD_PARTY.md` 无需新增运行时组件；若未来直接采用代码或资源，需先固定版本并按各自许可证补充归属。
