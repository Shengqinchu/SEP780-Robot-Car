# SEP 780 Arduino 4WD 小车

基于 Freenove FNK0041 的课程开发项目。先建立原厂功能基线，再实现并验证团队自己的改进。

GitHub 私有仓库：[Shengqinchu/SEP780-Robot-Car](https://github.com/Shengqinchu/SEP780-Robot-Car)。

> 2026-09-13 晚：usb_check 已成功上传到 COM5，实际收到两条推进心跳及问号查询应答；另做 8 秒只读采集，收到 8 条连续心跳，无检测到复位。[实测摘要](artifacts/2026-09-13-usb-hardware-check.json)。

主控 USB 下载/通信已通过，不代表整车功能通过。电池尚未到，实际舵机归中、电机/传感器、循迹与避障测试仍未执行；LED 物理闪烁也未由现场观察确认。电脑端已有 CLI、pySerial API、日志、端口锁及离线/CI 验证，具体记录见开发日志。

## 从哪里开始

- [开发日志](DEVLOG.md)：实际操作、问题、解决办法及验证状态。
- [上电与装配检查](docs/bring-up.md)：电池未到时能做什么，哪些步骤必须等待。
- [USB 串口自动调试](docs/serial-automation.md)：不用 IDE 点击的查询、日志、离线测试与安全门槛。
- [测试清单](docs/test-plan.md)：逐项记录真实结果，不提前打勾。
- [项目计划](docs/project-plan.md)：原厂基线与拟新增功能的边界。
- [自动化工具与开源选型](docs/tooling-research.md)：45 项 CLI/API/MCP/Skill/机器人项目比较，含源码检查和采用建议。
- [来源与许可](THIRD_PARTY.md)：原厂代码来源、固定版本及许可。
- [GitHub 编译验证](https://github.com/Shengqinchu/SEP780-Robot-Car/actions/runs/34784847884)：固定版本工具链的远端复现结果。

## 电脑端命令

在本项目目录打开 PowerShell 7：

```powershell
# 安装隔离的、固定版本的工具链，不改变全局 Arduino 环境
./scripts/Setup-Toolchain.ps1

# 校验原厂源码快照、程序清单、脚本语法和烧录保护
./tests/Check-Repository.ps1

# 编译全部原厂示例和项目 USB 检查程序，不接板也可以运行
./scripts/Build.ps1 -All

# 只读列出串口，不会烧录
./scripts/List-Boards.ps1

# 独立主机环境、离线测试与只读串口枚举
./scripts/Setup-Host.ps1
./tests/Test-Host.ps1
./scripts/Serial.ps1 -Action self-test
./scripts/Serial.ps1 -Action list
```

脚本当前支持 x64 Windows 和 x64 Linux。工具和编译缓存放在用户缓存目录；可通过 `SEP780_TOOL_ROOT` 指定另一个独立目录。不要指向其他项目已有的 Arduino 数据目录。

Windows 电脑另已准备 Arduino IDE 2.3.10。可以运行 `./scripts/Open-IDE.ps1` 打开本地 IDE；CLI 构建是本项目固定版本验证的依据。

## 程序入口

| 名称 | 用途 | 硬件注意事项 |
| --- | --- | --- |
| `usb_check` | 自编写的串口心跳及板载 LED 检查，115200 波特率 | 无电池/外接电源，车板 POWER 关、蓝牙移除；只接主控 USB |
| `servo_center` | 官方装配用 90 度归中 | 真实归中需要正确接线及供电 |
| `motor_test` | 官方前进、后退、转向测试 | 上电后会自行转动；四轮架空 |
| `tracking_sensor` | 三路循迹传感器读数 | 原厂示例，9600 波特率 |
| `ultrasonic_test` | 超声波距离读数 | 同时自动转动舵机，不是静态测距 |
| `line_following` / `obstacle_avoidance` | 原厂自动循迹 / 避障 | 确认装配并在受控场地测试 |
| `ir_car` / `bluetooth_car` | 原厂遥控综合示例 | 上传时移除蓝牙模块 |
| `rf_car` / `rf_controller` | 可选 RF 车端 / 遥控器端 | 实际是否有独立 RF 遥控器尚待确认 |

完整路径见 [programs.json](programs.json)。日常命令例如：

```powershell
./scripts/Build.ps1 -Program servo_center
```

烧录必须提供实际串口和明确的硬件确认参数，见 [上电检查](docs/bring-up.md)。本项目没有后台自动烧录、串口自动选取或自动控制小车的逻辑。

## 仓库内容

- `firmware/`：项目新增程序，和原厂代码分开。
- `host/`：pySerial USB 检查 API 和固定依赖；不是固件或运动控制器。
- `vendor/freenove/`：固定提交的原厂示例和依赖压缩包，保留原作者信息。
- `scripts/`、`tests/`：可复现准备、编译和仓库检查。
- `docs/`、`DEVLOG.md`：计划、装配门槛、测试与开发过程。
- `research/`：GitHub 检索范围、固定版本和来源证据；不是已安装依赖清单。
- `artifacts/`：可分享的精简验证记录；原始机器日志在被忽略的 `artifacts/local/`。

不上传课程教材、录课、个人截图、支付信息、访问凭证、IDE 安装包和编译产物。旧 `Shengqinchu/AutoRC` 未修改，此阶段不引入 Raspberry Pi 或 OpenCV 依赖。

## 协作与提交

每次实质改动同步追加开发日志，注明原厂、团队和 AI 辅助贡献。提交前执行仓库检查与受影响程序编译，硬件结果只依据实际观察记录。课程最终提交格式和 AI 使用要求以老师/Avenue 的明确要求为准，GitHub 上传不等于已提交课程作业。
