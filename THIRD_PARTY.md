# 来源与许可

## 原厂快照

- 来源：[Freenove/Freenove_4WD_Car_Kit](https://github.com/Freenove/Freenove_4WD_Car_Kit)。
- 固定提交：`a035ca380a9218d0a88aab635a58b9a3c738940f`。
- 导入范围：`Sketches/`、`Libraries/`、`LICENSE.txt`。
- 文件清单及 SHA-256：[vendor/freenove-manifest.json](vendor/freenove-manifest.json)。
- 根许可为 CC BY-NC-SA 3.0，原文保留在 [vendor/freenove/LICENSE.txt](vendor/freenove/LICENSE.txt)。依赖库自身的许可及源文件声明仍然适用，保留在原始压缩包内，不统一改为项目自有许可。

原厂源码未修改，不把其循迹、避障、遥控等功能描述为团队原创。后续改进放在 `firmware/`，明确引用来源并记录差异；派生内容遵守对应许可。

## 固定工具链

版本和官方下载地址、校验值见 [toolchain.lock.json](toolchain.lock.json)：Arduino CLI 1.5.1、Arduino AVR Boards 1.8.6、Servo 1.2.2，以及厂商附带的四个库包。

RF24 使用厂商提供的 1.3.2。IRremote 使用同一快照附带版本，不能直接替换为当前最新版并假定旧 API 仍兼容。

## 新增工作

`firmware/usb_check`、构建脚本、检查脚本及开发文档由本课程项目新增，使用了 AI 辅助编写和核验。仓库为私有协作用途，未对独立新增内容另行授予公开开源许可；不影响任何第三方原有授权。

## 调研候选与已采用依赖的区别

2026-09-13 的 [工具选型报告](docs/tooling-research.md) 和 `research/` 只记录候选、来源及审阅结果。本轮没有把候选 MCP、Skill、视觉/控制库或 AutoRC 实现复制到本项目代码，也未改变原厂许可或现有依赖锁。完整第三方源码/README 缓存在被忽略的 `.cache/`，不随本仓库发布。后续真正采用时，再在这里逐项列明版本、许可证、导入路径和改动。

## 已采用的主机依赖

- pySerial 3.5，[官方仓库](https://github.com/pyserial/pyserial)、[PyPI 固定版本](https://pypi.org/project/pyserial/3.5/)。许可为 BSD-3-Clause，许可正文随 wheel 安装在虚拟环境中。
- 安装文件 `pyserial-3.5-py2.py3-none-any.whl`，SHA-256 `c4451db6ba391ca6ca299fb3ec7bae67a5c55dde170964c7a14ceefec02f2cf0`，锁在 `host/requirements.lock`；本机和 CI 均使用 require-hashes 安装。
- `host/serial_tool.py` 及测试、PowerShell 接入由本项目新增并经 AI 辅助编写；未复制第三方 MCP 实现、未修改 pySerial 源码。依赖/环境在 `.local`，不上传二进制或 site-packages。

## 安卓构建与运行时

- 安卓 App 使用 Android 平台自带的 BLE GATT 与 `SpeechRecognizer` API，没有引入第三方蓝牙、语音或 UI 运行库。
- Android Gradle Plugin 8.8.2、Gradle 8.10.2、Command-line Tools 12.0、Android SDK 35、Build Tools 35.0.0 和 JUnit 4.13.2 固定在 `android-toolchain.lock.json` 与 Gradle 配置中。
- Gradle 和 Google 命令行工具的官方下载地址及 SHA-256 固定；SDK 包由 `sdkmanager` 按固定包名安装。本机 SDK、Gradle 缓存、APK 和调试签名均被忽略，不进入仓库。
- `mobile/android`、协议映射、有限词表、BLE 分片/续租和测试由本项目新增并经 AI 辅助编写。系统语音服务可能由设备厂商或用户选择的服务提供商实现，不随 App 分发。
- 2026-09-21 的遥控设计比较了 OpenBot（MIT）、DonkeyCar（MIT）、controlwear Virtual Joystick Android（Apache-2.0）和 BradenBoucher/rc-car（MIT）；详见 [调研记录](research/rc-controller-2026-09-21.md)。本项目只采用原子遥控、差速混控、死区、斜率限制和松手归零等通用设计思想，没有复制这些项目源码，也没有把它们加入构建依赖。

## 自定义控制器与测试工具

- `firmware/robot_car/controller.*`、`protocol.*`、主机 API、回放及测试由本项目新增，采用 AI 辅助实现和核验。软件结果和现场实测分开记录在开发日志中。
- `fnk0041_io.cpp` 的引脚/左右电机极性依据固定原厂 `Sketches/03.2_Automatic_Tracking_Line/Freenove_4WD_Car_for_Arduino.*`；`ir_input.cpp` 的遥控键码依据 `Sketches/04.3_Multifunctional_IR_Remote_Car/Freenove_IR_Remote_Keycode.h`。硬件适配与键码部分按原厂 CC BY-NC-SA 3.0 保留来源；没有复制原厂完整循迹/避障控制循环。
- 项目固件沿用已固定的 Servo 1.2.2 和 IRremote 2.2.3。没有更新原厂依赖，没有移植 AutoRC 代码。
- [ThrowTheSwitch/Unity 2.6.1](https://github.com/ThrowTheSwitch/Unity/tree/cbcd08fa7de711053a3deec6339ee89cad5d2697)，MIT。四个源码/许可文件逐字节保存在 `vendor/unity`，许可证见 [LICENSE.txt](vendor/unity/LICENSE.txt)，SHA-256 锁在 [native.lock.json](native.lock.json)。这是 C/C++ 单元测试框架，不是 Unity 游戏引擎。
- [Zig 0.13.0](https://ziglang.org/download/0.13.0/release-notes.html) 作为本机/CI 的 C/C++ 编译器，Windows/Linux 官方下载 SHA-256 固定在 `native.lock.json`。工具及其上游许可证随原包保留在本机缓存，不作为机器人运行依赖上传。

## 舵机小幅动作诊断

- `firmware/servo_check/servo_check.ino` 依据同一固定原厂快照的 `00.0_Servo_90`（舵机 D2）和 `01.1.3_Car_Move_and_Turn`（电机 PWM D5/D6）硬件映射新增，按 CC BY-NC-SA 3.0 保留来源。
- 新增单轮 `90/80/90/100/90` 度命令序列、零电机输出和串口命令日志，不修改原厂文件。每次启动/复位自动执行一轮，串口记录不是舵机角度反馈。

## 电机一次性动作诊断

- `firmware/motor_check/motor_check.ino` 依据固定原厂 `01.1.3_Car_Move_and_Turn` 的 D3/D4 方向脚、D5/D6 PWM 脚及左右极性基线新增，按 CC BY-NC-SA 3.0 保留来源；本车实测后同时反转两侧正向定义，原厂文件不变。
- 诊断程序不复制原厂循环动作：每次启动先保持停止 3 秒，只按原厂基线 PWM 200 正向运行 1 秒，随后永久归零；不读取超声波、循迹、电池或其他传感器，并按原厂 A0 共用规则保持蜂鸣器静音。它只用于四轮架空时确认电机接线与方向，完成后需重新上传正式 `robot_car`。

## 官方资料

- [装配与烧录顺序](https://docs.freenove.com/projects/fnk0041/en/latest/fnk0041/codes/tutorial/0_Software,_Assembly_and_Play.html)
- [固定版本教程 PDF](https://github.com/Freenove/Freenove_4WD_Car_Kit/blob/a035ca380a9218d0a88aab635a58b9a3c738940f/Tutorial.pdf)
- [电池说明](https://github.com/Freenove/Freenove_4WD_Car_Kit/blob/a035ca380a9218d0a88aab635a58b9a3c738940f/About_Battery.pdf)
- [Arduino CLI 官方文档](https://docs.arduino.cc/arduino-cli/)
- [Freenove 蓝牙控制说明](https://docs.freenove.com/projects/fnk0041/en/latest/fnk0041/codes/tutorial/6_Bluetooth_control.html)
- [Android 蓝牙权限](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions)
- [Android BLE GATT 连接](https://developer.android.com/develop/connectivity/bluetooth/ble/connect-gatt-server)
- [Android SpeechRecognizer](https://developer.android.com/reference/android/speech/SpeechRecognizer)

完整原厂手册另外保存在本机 `reference/`，不随仓库重复上传。课程资料仍留在上级课程归档中。
