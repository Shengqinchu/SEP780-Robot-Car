# SEP780 Robot Car

**中文** | [English](README.en.md)

基于 Freenove FNK0041 的 Arduino 四驱小车：沿黑线行驶，遇到障碍停车等待，路线恢复后继续前进。通过套件自带的红外遥控器或电脑串口切换控制，传感器数据和状态变化可记录、回放与分析。

## 功能

| 功能 | 工作方式 |
| --- | --- |
| 循迹 | 三路红外传感器识别黑线，分别调整左右轮速度 |
| 遇障停车 | 前方距离低于阈值时停止驱动，持续确认空间恢复后继续循迹 |
| 脱线处理 | 脱线立即停车；短暂丢线可恢复，持续脱线或遇到歧义线型需重新启动 |
| 手动控制 | 红外按键或串口控制前进、后退和转向，指令超时停车 |
| 故障处理 | 无回波、读数过期、低电压和异常指令触发停车 |
| 调试记录 | 串口遥测、CSV 导出、相同 C++ 控制代码的离线场景回放 |

硬件使用现有套件的 Uno 兼容主控、四个电机、三路循迹板、超声波传感器、舵机和红外遥控器。这一版不需要摄像头、树莓派或额外模块。

## 快速开始

在仓库根目录使用 **PowerShell 7**，并准备 **Python 3.10+**。支持 x64 Windows 和 Linux。以下步骤不需要连接小车。

```powershell
git clone https://github.com/Shengqinchu/SEP780-Robot-Car.git
cd SEP780-Robot-Car

./scripts/Setup-Toolchain.ps1
./scripts/Setup-Host.ps1
./scripts/Setup-Native.ps1

./scripts/Build.ps1 -Program robot_car
./tests/Test-Control.ps1
./tests/Test-Host.ps1
./scripts/Simulate.ps1
```

首次运行会下载固定版本的工具；后续开发直接运行编译和测试命令。私有仓库成员需先登录 GitHub。

回放读取 [line_course.csv](scenarios/line_course.csv)，覆盖转弯、遇障等待、恢复、脱线、无回波和超时。结果保存在 `artifacts/local/line-course-replay.csv`：

```text
following -> obstacle -> clear_wait -> following
following -> line_lost -> following
manual    -> remote_timeout
```

这是传感器输入驱动的逻辑回放，用于检查程序决策；实际车速和停车距离在到货校准时测量。

## 在小车上运行

电池到货后，按[校准指南](docs/calibration.md)完成舵机归中、车轮方向和传感器检查，再上传 `robot_car`。该固件启动时将超声波转头归中，轮子保持停止，等待启动指令。

| 红外按键 | 操作 |
| --- | --- |
| `1` | 从停止状态进入循迹 |
| `2` | 从停止状态进入手动控制 |
| 方向键 | 手动模式下按住前进、后退或原地转向 |
| 电源键 / `0` / 中间播放暂停键 / `OK` | 停车；更换模式前也先停车 |

电脑端通过 `scripts/Robot.ps1` 查看遥测或执行限时控制。接线、上传、命令示例和参数调整统一放在[校准指南](docs/calibration.md)，串口格式见[协议文档](docs/control-protocol.md)。

## 开发与测试

```powershell
./tests/Check-Repository.ps1
./tests/Test-Control.ps1
./tests/Test-Host.ps1
./tests/Test-Docs.ps1
./scripts/Simulate.ps1
./scripts/Build.ps1 -All
```

- **C++ / Unity：**测试实际控制逻辑、命令解析、红外输入和硬件适配层的模拟 I/O。
- **Python / unittest：**测试串口会话、超时、异常退出、端口锁和数据导出。
- **Arduino CLI：**编译全部原厂示例和自定义固件。
- **GitHub Actions：**在 Linux 上重复软件验证，查看[运行结果](https://github.com/Shengqinchu/SEP780-Robot-Car/actions/workflows/compile.yml)。

**当前进度：**主控 USB 烧录和通信已实测通过；自定义控制软件已完成离线验证，下一步是电池供电下的实车校准。

## 代码结构

```text
firmware/robot_car/    控制逻辑、协议和 FNK0041 硬件适配
firmware/usb_check/    独立 USB 连通性检查
host/                 Python 串口 API、回放和 CSV 导出
scripts/              安装、编译、上传与操作入口
tests/                C++、Python 和文档检查
scenarios/            可重复的传感器输入场景
vendor/               固定版本的原厂示例和 Unity
docs/                 校准、架构、协议和测试指南
```

日常调整集中在 [config.h](firmware/robot_car/config.h)：车速、左右轮补偿、避障距离和超时参数都在这里。硬件读写与控制决策分开，修改决策后可以先在电脑上测试。

## 进一步阅读

- [校准指南](docs/calibration.md)：电池到货后的操作顺序。
- [控制逻辑](docs/controller.md)：状态转换、引脚和参数。
- [验证清单](docs/test-plan.md)：软件覆盖与实车验收项目。
- [开发日志](DEVLOG.md)：过程、问题、解决办法和验证记录。
- [第三方来源](THIRD_PARTY.md)：原厂代码、依赖版本与许可。
