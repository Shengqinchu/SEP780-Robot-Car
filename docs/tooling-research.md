# SEP 780 小车：自动化开发工具与开源复用选型

研究日期：2026-09-13，America/Toronto。适用平台：Windows、Freenove FNK0041、Arduino Uno 兼容 ATmega328P。本文是选型与实施建议，不代表新增功能已经实现或实车通过验收。

## 1. 结论

**不需要靠截图和点击 Arduino IDE 开发。官方 Arduino CLI 已经可以完成机器可读的设备枚举、编译、库管理、烧录和串口监视，还提供 gRPC API。当前项目已经使用这条路线。** IDE 可以保留为人工查看代码的工具，不应成为自动化的必经环节。[^1]

推荐采用四层组合：**现有 Arduino CLI + 受控串口 API + 可离线测试的车端状态机 + GitHub CI/开发日志**。需要跨 AI 客户端调用时再增加 MCP；不为使用 MCP 而更换整套开发工具。

开源复用应优先解决实际问题：Freenove 保留硬件驱动基线；TaskScheduler 候选解决多个周期任务调度；PacketSerial/SerialTransfer 二选一解决需要时的分包；Unity 测试决策逻辑；OpenBot/Donkeycar 借鉴计算与执行分层。OpenCV 只作为后续电脑端视觉扩展，不放进 Uno。

基础改进不要求添购 Raspberry Pi、摄像头、声控板或调试探针。电池与正确供电仍是运动测试前提。MCP 是电脑端的操作接口，不会给 Arduino 增加算力、传感器或供电能力。

## 2. 当前事实与研究边界

| 项目 | 当前证据 | 不能据此推导的结论 |
| --- | --- | --- |
| USB 连接 | CLI 枚举到新增 COM5，VID/PID 为 1A86:7523；matching_boards 字段不存在 | 不能仅凭 USB 转串口标识证明具体 MCU、接线或 bootloader 正常 |
| 板型 | 套件资料采用 Uno 兼容平台，工程固定 `arduino:avr:uno` | CLI 仍显示 Unknown，不是本轮自动识别出了 Uno |
| 自动编译 | 本轮 `usb_check` 再编译成功，Flash 2318/32256、静态 RAM 193/2048 字节 | 不代表固件已上传，不是运行时 RAM 峰值 |
| 既有全量验证 | 早先 Windows 与 GitHub Linux 30/30 编译通过，链接保存在 README | 本轮没有重新执行全部 30 个程序的编译 |
| 断点调试 | 本轮 CLI `debug check --fqbn arduino:avr:uno --json` 返回 `debugging_supported:false` | 不表示所有 AVR 专用调试方法都不可能；只是不具备当前配置下开箱即用的该项支持 |
| 实物状态 | 已提供整车装配照片，电池最新已知状态为未到 | 未完成电机、舵机、循迹和避障功能验收 |

检索覆盖两轮 22 条中英文查询，搜索返回 822 条记录；与种子合并去重后记录 807 个公开仓库元数据。再经官方文档追链补充 Wokwi CLI，最终 45 个对象进入比较，包括原有私有 AutoRC。所有候选采集固定提交、README 和能取得的根许可证，重点审阅八个独立 MCP、四组 Skill，以及 Serial Studio/AutoRC 的关键入口。**这不是通读 807 个仓库，也不是 GitHub 全量穷尽。** 五个宽泛查询截断于前 100 项；MCP 芯片库、Alexa skill、CAN 汽车项目等噪声按用途排除。采集规则、失败记录和原始数量见 [research](../research/README.md)。

星数为该日 GitHub API 快照，不是质量、维护投入或 Uno 兼容性的保证。最后提交时间只说明有提交，不证明其修复了相关功能。本文区分“代码核对”“文档支持”和“本机验证”；没有安装、启动或实物测试任何候选 MCP。

## 3. CLI、API、MCP、Skill 分别负责什么

- **CLI**：运行确定命令，例如 compile；输出 JSON/退出码/日志，可被 Codex、PowerShell 和 CI 调用。
- **API**：程序接口。Arduino CLI 的 gRPC 适合持久服务；pySerial 适合电脑端串口读写、超时、缓冲和日志记录。不是去操作 IDE 的按钮。[^1][^2]
- **MCP**：把这些操作包装成 AI 可发现的工具，例如 compile、capture_log。真正的编译器、串口驱动和固件仍在下面。
- **Skill**：描述板型、流程、参数、验收及禁止事项的说明/脚本包。它本身不是驱动，也不是能自动识别电气风险的硬件控制器。

对单车、单 Windows 主机，目前启动受控 CLI 子进程比另外维护 gRPC daemon 更简单；以后有持续服务或多个客户端再评估 gRPC。MCP 的 readOnlyHint 等属于提示，不是强制隔离或用户授权的证明，必须看实现。[^3]

### 推荐操作接口边界

| 操作 | 接入方式 | 初期限制 |
| --- | --- | --- |
| `ports.list` | 现有 List-Boards / CLI JSON | 只枚举，不探测性开串口，不自动选第一个端口 |
| `firmware.compile` | 现有 Build 脚本 | 固定 Uno/core/libs，保存退出码和内存报告 |
| `tests.run_native` | 后续 Unity/主机测试 | 只允许运行明确的离线测试，不把通用板上测试归为只读 |
| `serial.open` / `serial.close` | 后续 pySerial 会话适配器 | 明确 COM5 等目标；先确认物理条件；打开端口可能复位 |
| `serial.capture` | 有时限、有字节上限的日志采集 | 一次一个串口所有者；落档需去除本机路径/个人数据 |
| `serial.query` | 仅允许当前固件支持的查询 | 初期只用 usb_check 的 `?`；不是任意发送电机指令 |
| `firmware.flash` | 已有 Upload 脚本 | 明确端口、程序和硬件确认，上传前释放串口 |
| 运动测试 | 后续单独定义的测试动作 | 电池、接线、架空/测试场地确认后才开放 |

已有上传脚本的确认参数可以减少误操作，但拥有 shell 权限的代理仍能直接调用底层程序；它不是不可绕过的系统安全边界。真正规则是先取得相应授权，再按确定目标执行，固件自身也必须默认停止并处理故障。

## 4. 开发、调试与测试工具比较

| 工具 | Stars | 功能与适配 | 许可/维护观察 | 决策 |
| --- | ---: | --- | --- | --- |
| [Arduino CLI](https://github.com/arduino/arduino-cli) | 5,023 | 官方编译/上传/JSON/gRPC；当前固定 1.5.1 已使用 | GPL-3.0；工程通过命令调用，不复制 CLI 实现 | **主工具，保留** |
| [PlatformIO Core](https://github.com/platformio/platformio-core) | 9,456 | Uno 构建、依赖和多环境测试；native/embedded 测试要区分 | Apache-2.0 | 完整备选；有多平台/测试管理需求再加，不立即迁移 |
| [pySerial](https://github.com/pyserial/pyserial) | 3,571 | Python 串口 API，适合限时采集、协议测试、CSV | 根文件实际 BSD-3-Clause，API 元数据未自动归类 | **推荐下一阶段使用**；需独立会话管理 |
| [Serial Studio](https://github.com/Serial-Studio/Serial-Studio) | 7,194 | 可视化遥测、TCP API/gRPC/MCP，适合演示与数据观察 | GPL 构建与商业 Pro 分开；官方二进制按 EULA 提供试用 | 可选，不把收费试用当成长期免费基础依赖 |
| [Microsoft VS Code Arduino 扩展](https://github.com/microsoft/vscode-arduino) | 1,191 | IDE 插件，不是必要的程序化接口 | 仓库已归档；最后提交 2024-09 | 不作为新项目基础 |
| [AVR8js](https://github.com/wokwi/avr8js) | 844 | JS AVR 模拟内核，可离线测试 CPU/数字引脚/时序 | MIT；不是整个 Wokwi 服务 | 需要模拟串口/定时器时再接入 |
| [Wokwi CLI](https://github.com/wokwi/wokwi-cli) | 66 | 官方仿真 CLI，带实验性 MCP，可操纵虚拟器件、检查串口输出 | CLI 为 MIT；云端仿真另需 token/额度 | **无电池时的仿真备选**；未配置账号令牌，不代替实车验收 |
| [simavr](https://github.com/buserror/simavr) | 1,784 | AVR/ELF 仿真，适合 MCU 级行为检查 | GPL-3.0；Linux/avr-gcc 路线更直接 | 当前 Windows 入门阶段次选 |
| [Unity](https://github.com/ThrowTheSwitch/Unity) | 5,375 | 嵌入式 C 单元测试，可测状态与边界；不是游戏引擎 | MIT | **推荐测试框架**，车端逻辑与 GPIO 分开后导入 |
| [ArduinoFake](https://github.com/FabioBatSilva/ArduinoFake) | 131 | 在主机 mock Arduino 调用，无需真板 | MIT；需相容的本机 C++ 编译器 | 只在确需 mock Arduino API 时补充 |

**Serial Studio 的成本边界需特别说明。** 所核对提交的 LICENSE 指出：默认 `BUILD_GPL3=ON` 为 GPL 版本；Pro-only 源码公开不等于赋予 GPL 使用权；官方预编译版包含 Pro 模块，以 EULA 提供每个 release 14 天试用。基础源码构建含 UART、常用图表、CSV 和本地 TCP/MCP API，但 Windows 自编译需要 Qt/C++/CMake 环境。可先以 pySerial + CSV 完成数据闭环，避免把项目进度绑定在 GUI 编译或付费授权上。[^4]

**仿真不替代底盘测试。** AVR8js 是 Wokwi 的 MCU 内核而非完整电路/物理引擎；Wokwi CI 还有独立账户/令牌/使用额度安排，不能从 MIT 内核推导服务无限免费。电机负载、电池压降、地面反光、轮胎打滑和超声波误差必须上实车测。[^5]

Wokwi 官方 CLI 的 `mcp` 子命令是另一种现成接口：操作对象是模拟器，不是真实 COM5。当前文档列免费用户每月 50 分钟仿真额度，需 `WOKWI_CLI_TOKEN`；运行会把固件提交到云端模拟器，使用前应确认这适合课程/私有代码。没有在本轮申请令牌或上传固件到 Wokwi。[^14]

**串口日志调试与断点调试不是一回事。** 当前 Uno 配置可以通过程序日志、传感器读数、测试指令定位问题；不能因为安装一个 MCP，就获得 STM32 + ST-Link 那种断点/变量内存调试。无需因此先买探针或改烧 bootloader。

## 5. MCP 候选比较

| MCP | Stars | 实际底层 | 优点 | 对本项目的限制与选择 |
| --- | ---: | --- | --- | --- |
| [hardware-mcp/arduino-mcp-server](https://github.com/hardware-mcp/arduino-mcp-server) | 17 | Node/TypeScript + Arduino CLI | 编译、上传、会话串口、电气 preflight、内部端口协调 | 与当前技术栈接近；需禁用自动装 core/跳过检查。**一站式 Arduino MCP 候选** |
| [jl-codes/platformio-mcp](https://github.com/jl-codes/platformio-mcp) | 51 | Node/TypeScript + PlatformIO | 策略、审批、日志、任务、仪表盘；实现较完整 | 引入新构建体系；build_only 仍需检查 run_tests 的实物副作用。**工程扩展备选** |
| [Adancurusul/serial-mcp-server](https://github.com/Adancurusul/serial-mcp-server) | 91 | Rust + 串口 | 独立 CLI、持久会话、受限 JSON 宏、离线模拟宏 | 不编译 Arduino；开端口和控制线仍需确认。**独立串口 MCP 优先试点对象** |
| [es617/serial-mcp-server](https://github.com/es617/serial-mcp-server) | 20 | Python + pySerial | 结构化串口工具、trace、插件默认禁用 | 多一层 MCP/插件机制；当前直接 pySerial 已够用。备选 |
| [qarnet/serial-mcp](https://github.com/qarnet/serial-mcp) | 9 | Rust | 协议分帧、接收会话、丢字节统计、启动捕获 | 功能多；捕获启动可能含复位；Windows 仍需本车实测。暂缓 |
| [Rance-OwO/Serial-Agent](https://github.com/Rance-OwO/Serial-Agent) | 40 | VS Code 扩展 + 本地 Bridge + MCP | 中文嵌入式工作流、串口日志、工具链调用 | 原生构建/烧录面偏 Keil/J-Link/ST-Link，不是 Uno CLI 的直接替代。不主选 |
| [niradler/arduino-mcp](https://github.com/niradler/arduino-mcp) | 2 | Python FastMCP + CLI | 简洁、功能覆盖广 | 自动选端口回退与“只读验证实际开串口”；仅元数据声明 MIT。默认不接入 |
| [amahpour/arduino-mcp-server-simple](https://github.com/amahpour/arduino-mcp-server-simple) | 6 | Python FastMCP + CLI | 易读，适合理解包装方法 | 串口调用每次重开；README 的测试环境为 macOS/Cursor。作原理参考 |

除特别注明者，以上七个有完整根许可证的候选均为 MIT。实际来源、固定 SHA、代码路径见 [关键入口检查](../research/source-audit-2026-09-13.md)。不把“能安装”“tests 文件存在”或“有 Windows 构建”写成当前设备已可用。

有三项发现直接影响选择：

1. `niradler/arduino-mcp` 的 verify_port 标注只读，却用 `serial.Serial(...)` 开关端口；Uno 自动复位风险与 pySerial 官方说明吻合。当前有多个蓝牙串口，更不能依赖它的第一端口回退。
2. `hardware-mcp` 确实有 preflight，但部分电气信息可选，而且提供跳过参数；它不能靠软件推断照片背后的接线，也不能替代用户的物理确认。
3. `platformio-mcp` 的 build_only 允许 `run_tests`，实际可运行未限定环境的 `pio test`。PlatformIO 官方区分 native 与 embedded，后者可以烧录并在板上执行；必须限制为已核对的 native 测试，或把板上测试纳入硬件审批。[^6]

这些是静态核对及其工程推论，不是本轮已触发的故障。现阶段不安装多个 MCP 抢同一串口，也不赋予通用工具“自动修复驱动、随意更新库、任意烧录”的权限。

## 6. Skill 候选比较

| Skill 项目 | Stars | 可取部分 | 适配结论 |
| --- | ---: | --- | --- |
| [wedsamuel1230/arduino-skills](https://github.com/wedsamuel1230/arduino-skills) | 21 | CLI、版本记录、硬件测试与编译证据分级 | MIT；优先参考 CLI、串口与测试流程，不整包装入无关功能 |
| [ripred/arduino-cli-skills](https://github.com/ripred/arduino-cli-skills) | 4 | CLI 分模块，含 daemon/gRPC、配置和维护 | MIT；可作命令索引；不要搬用 Nano/macOS 默认值或自动升级锁定工具链 |
| [Sunwood-ai-labs/m5stack-arduino-cli-skill](https://github.com/Sunwood-ai-labs/m5stack-arduino-cli-skill) | 10 | Windows 枚举与 Unknown 诊断思路 | MIT；板型是 ESP32/M5Stack，不能执行其 esptool/装库步骤到本车 |
| [rockets-cn/unihiker-k10-skills](https://github.com/rockets-cn/unihiker-k10-skills) | 6 | 厂商资料和工具链一起固定 | K10/ESP32 专用，无根许可证；不复制、不安装其板级工作流 |

**建议后续建立一个很小的本项目 Skill，而不是收集大量通用 Skill。** 它只引用已有 Build/List-Boards/Upload、版本锁、上电检查和 DEVLOG，再增加限定的串口采集步骤。本文仅确定这种设计，没有在 Codex 全局安装 Skill 或修改 MCP 配置。

## 7. 能组合进自己项目的开源模块

### 7.1 车端库

| 项目 | Stars | 可复用能力 | 许可与硬件适配 | 决策 |
| --- | ---: | --- | --- | --- |
| [TaskScheduler](https://github.com/arkhipenko/TaskScheduler) | 1,654 | 协作式周期任务 | BSD-3-Clause；文档有 Uno 平台数据；不是抢占式 RTOS | 多任务开始增加时优先评估；不能自动消除回调内的阻塞 |
| [AceRoutine](https://github.com/bxparks/AceRoutine) | 189 | 低内存无栈协程 | MIT；独特宏/生命周期写法 | TaskScheduler 的替代，不同时加两个调度层 |
| [Arduino PID Library](https://github.com/br3ttb/Arduino-PID-Library) | 2,202 | 经典 PID 控制 | README 声明 MIT；导入时补核完整许可；接口本身不提供测量 | 有循迹误差信号及测试依据再用 |
| [QuickPID](https://github.com/Dlloydev/QuickPID) | 255 | PID、抗积分饱和等 | MIT；比经典 PID 功能多，仍需采样/调参 | PID 备选，初期不为高级参数增加调试负担 |
| [PacketSerial](https://github.com/bakercp/PacketSerial) | 306 | COBS/SLIP 串口分包 | MIT；分帧不是 CRC、身份验证或动作超时 | 数据协议需要二进制时优先小范围评估 |
| [SerialTransfer](https://github.com/PowerBroker2/SerialTransfer) | 486 | 非阻塞分包、CRC-8、PC 对接路线 | MIT；核对缓冲区与 AVR/PC 数据类型宽度 | 与 PacketSerial 二选一；更希望现成 CRC 时考虑 |
| [ArduinoJson](https://github.com/bblanchon/ArduinoJson) | 7,213 | JSON 解析/输出 | MIT；作者建议 8 位 MCU 保留 v6，v7 不以小体积为重点 | 首版车端不引入；电脑端直接处理 JSON/CSV |
| [Pololu QTRSensors](https://github.com/pololu/qtr-sensors-arduino) | 150 | 反射传感器标定与位置计算 | 许可文件为 MIT；面向 Pololu QTR，非本车数字循迹板的现成驱动 | 借鉴标定/误差计算方法，不直接换驱动 |

ArduinoJson 的选择依据是作者当前迁移说明，不是“星数高就必须装最新”。同样，TaskScheduler 是合作调度，原厂避障代码里的长 delay、等待舵机和 pulseIn 超时必须单独处理，否则状态机仍可能迟迟不响应停止指令。[^7]

本车循迹是三个数字输入，原厂注释为黑线 0、白底 1；不是相机识别。可建立左/中/右偏差及脱线/交叉线状态，但分辨率有限。现有材料没有确认轮速编码器，所以不能把 PWM 调速写成闭环转速控制；循迹 PID 与轮速 PID 是不同问题。已核对实际引脚，后续导入 GPIO、PWM 或定时器相关库时必须检查冲突。[^8]

### 7.2 电脑直接控制 GPIO 的路线

| 项目 | Stars | 机制 | 结论 |
| --- | ---: | --- | --- |
| [Firmata Arduino](https://github.com/firmata/arduino) | 1,621 | 主机协议 + 车端 Firmata 固件，LGPL-2.1 | 可以做台架 GPIO 实验，但不是在现有自主固件旁“无侵入加个 API” |
| [Johnny-Five](https://github.com/rwaldron/johnny-five) | 13,410 | Node.js 机器人 API，Uno 常用 Firmata；根许可 MIT | 高星且适合原型；主机驱动方式改变架构，不作脱离电脑的自主车基础 |
| [pymata4](https://github.com/MrYsLab/pymata4) | 77 | Python Firmata 客户端，AGPL-3.0 | 已归档，不新引入 |
| [Telemetrix](https://github.com/MrYsLab/telemetrix) | 93 | Python 客户端 + 对应 MCU 服务固件，AGPL-3.0 | 原理可参考；不是通过串口就能控制任意现有固件 |

当前保留自主运行比远程 GPIO 更重要。电脑拔线后基础循迹/避障应继续按车端规则执行；只有远程驾驶模式需要通信心跳，超时必须停止。不要把“所有模式都要求电脑心跳”错误加入脱机自主模式。

### 7.3 高星整车工程

| 项目 | Stars | 可以借鉴 | 为什么不整套搬来 |
| --- | ---: | --- | --- |
| [OpenBot](https://github.com/ob-f/OpenBot) | 3,492 | 手机感知/高层决策，微控板执行的分层；采集数据流程 | MIT；其 Android/底盘设计与当前硬件不同，仍需映射电机接口和供电 |
| [Donkeycar](https://github.com/autorope/donkeycar) | 3,502 | 模块化流水线、记录驾驶数据、校准、训练与回放 | MIT；以 Python/车载计算机为主，不能运行在 2 KB SRAM 的 Uno 上 |
| [linorobot2](https://github.com/linorobot/linorobot2) | 1,014 | 差速底盘抽象、ROS2 导航层、仿真/实车接口分开 | Apache-2.0；ROS2/Nav2/SLAM 与传感器栈远超本次基础需求 |
| [micro_ros_arduino](https://github.com/micro-ROS/micro_ros_arduino) | 575 | ROS2 的 MCU 接口架构 | Apache-2.0；官方支持表未列 AVR Uno，不能当成可直接安装的 Uno 库 |
| [rosserial](https://github.com/ros-drivers/rosserial) | 549 | 旧 ROS1 与 MCU 串口消息桥 | 按子包许可证核对；ROS1 Noetic 已于 2025-05-31 EOL，不为这辆新车搭旧栈 |

OpenBot/Donkeycar 值得学习架构，不意味着应先买它们的全部硬件。复用接口思想与完整移植运行环境的成本不同。ROS1 EOL 是维护风险，不代表旧程序会立即停止运行；这里只是不选择它作为新项目基础。[^9]

### 7.4 视觉、语音与现有代码

| 项目 | Stars | 对本项目的用途 | 决策 |
| --- | ---: | --- | --- |
| [OpenCV](https://github.com/opencv/opencv) | 90,818 | PC 上识别 ArUco、颜色、线；Apache-2.0 | 视觉扩展首选，不装进 Uno |
| [opencv_contrib](https://github.com/opencv/opencv_contrib) | 10,191 | 补充视觉模块；Apache-2.0 | 依所选 OpenCV 版本/API 判断需要，不同时安装相互冲突的 Python 包 |
| [AprilTag](https://github.com/AprilRobotics/apriltag) | 2,516 | 标记 ID 与位姿；BSD-2-Clause | 可替代标记路线；README 官方支持以 Linux 为主，Windows 要额外验证 |
| [Vosk](https://github.com/alphacep/vosk-api) | 15,127 | PC/手机离线语音转命令；API 为 Apache-2.0，模型另核许可 | 语音“停止/启动”备选；不让语音绕过车端安全状态 |
| [Freenove 原厂](https://github.com/Freenove/Freenove_4WD_Car_Kit) | 39 | 与这辆车实际匹配的引脚、驱动和基础例程 | CC BY-NC-SA 3.0 根许可；**保留为基线**，匹配比星数更重要 |
| [现有 AutoRC](https://github.com/Shengqinchu/AutoRC) | 私有 | 黑线检测、PC/Pi 分层、标志到命令映射 | MIT 根许可，依赖另计；选择性改造，不更动旧仓库 |

**AutoRC 实际能复用什么？** 所核对提交 `90340e6` 的 `current/core/lane_detector.py` 是 HSV 黑色区域、形态学和轮廓质心的双黑线居中检测；`current/pc/yolo_server.py` 使用 Ultralytics YOLO 识别 Stop/Red Light/限速并回传 STOP/SLOW/FAST。没有依据把它称为现成 ArUco 工程。其默认权重 `pc/best.pt` 不在当前完整 Git 树中，尚未取得外部权重。[^10]

迁移旧程序至少要改三处：树莓派 PWM/舵机转向改为 Uno 左右差速命令；视频来源替换掉原 Pi 摄像头流；通信增加帧边界、限长、超时和断链处理。原 YOLO 服务有网络 pickle 解码，未审定输入可信性之前不直接移植这条网络路径；本次也没有运行它。旧仓库的 MIT 不会把 Ultralytics 等依赖自动变成 MIT。

若只要“看到某个标记就停车/变速”，**ArUco 比重新训练 YOLO 更适合作为第一版视觉验证**：直接使用打印的 ID 标记，先验证距离、角度、光照下的识别和错误处理；这是基于任务复杂度的工程选择，不是已经测出的性能比较。需要位姿/距离时还要相机标定和实际标记尺寸，不能只凭 ID 推算距离。[^11]

没有确认现有可用摄像头/旧手机，因此不承诺视觉零新增硬件。可以先用已有图像做离线算法验证；若用电脑固定摄像头看标记，那是电脑视觉控制演示，不能描述成已经实现车载自主视觉。基础车稳定后再决定是否值得加无线视频链路或计算板。

## 8. 我们自己的版本应做什么

建议首个自主版本做成**可测量、可解释的安全循迹车**，不是把多个原厂例程依次运行。原厂负责可追溯的底层驱动，团队负责统一决策、错误状态、协议、测试与参数比较。

推荐状态为 `IDLE / LINE_FOLLOW / OBSTACLE_HOLD / LINE_LOST / REMOTE / FAULT`。上电默认 IDLE；模式转换有明确条件；障碍停车与恢复有迟滞/连续有效读数要求；脱线不无限盲转；远程控制过期停车，重新连接不自动恢复旧速度。超声波无回波须标为无效读数并按次数/时间策略处理，不把 0 或溢出值当作正常距离。

```text
Codex / project workflow
  -> fixed Arduino CLI scripts -> build / reviewed upload
  -> bounded serial session -> commands / telemetry / test evidence
                                  |
                         Uno autonomous firmware
                   sensors -> state machine -> motors

Optional later: PC camera -> OpenCV marker event -> serial command
```

| 从开源取的部分 | 自己必须完成的部分 | 可交付证据 |
| --- | --- | --- |
| Freenove 驱动/原厂例程 | 实际引脚适配、校准和基线对照 | 原厂测试表、参数、失败视频/记录 |
| TaskScheduler 或现有 millis 模式 | 非阻塞任务切分、状态转换、故障处理 | 循环耗时、停止响应、输入失效测试 |
| 单一通信库/受限短文本协议 | 模式、序号/应答、范围校验、超时和复连规则 | 正常/残包/超长/重复/断线回放用例 |
| Unity | 独立于 GPIO 的决策模块与测试场景 | CI 测试报告，失败回归用例 |
| pySerial/可选串口 MCP | 一个串口所有者、限时采集、可分享结果 | CSV/JSON 摘要、命令日志、DEVLOG |
| OpenBot/Donkeycar 的分层思想 | 实际车体接口与自主/远程责任边界 | 架构说明、脱机运行演示 |

首版无需一次装齐所有候选库。先使用易检查、限长的基础串口命令；出现二进制/校验需求时，再在 PacketSerial 与 SerialTransfer 中选一个，并跑端到端编码/解码测试。不要在每种通信库之间再叠套自定义层。Uno 的 2 KB SRAM 是主要预算约束，每引入一个库都重新编译检查静态 RAM，并另外评估堆栈、缓冲和运行时余量。[^12]

课程得分最终取决于老师认可的范围、团队原创贡献和实际表现。本文没有新核对评分表，也不保证某组功能必得某个分数。比较原厂与改进版的成功率、失败类型、停车响应和恢复表现，比单纯展示高星依赖清单更有工程说明价值。

## 9. 执行顺序与验收门槛

以下是实施估计，不是已完成工作；按四人协作、每日有连续调试时间且硬件正常估算，等待电池不计入有效工时。

| 阶段 | 预计投入 | 通过条件 |
| --- | --- | --- |
| 裸板 USB 检查 | 约半天内 | 确认接线/隔离、显式选 COM5，授权后上传 usb_check，收到启动标识、心跳和查询应答 |
| 串口自动化与离线测试骨架 | 1-2 个工作日 | 假设备/回放测试通过；一次单会话，超时能退出；无隐式扫描开端口或烧录 |
| 原厂实车基线 | 电池到后 1-2 个工作日 | 舵机归中，架空验证左右/正反转，独立测循迹与超声波 |
| 自主状态机与调参 | 约 3-5 个工作日 | 循迹、停车、脱线、远程超时和模式切换均可复现，日志对应实际行为 |
| 可选视觉 | 再加约 2-4 个工作日，前提是视频来源可用 | 离线标记测试、通信联调、断流停车；明确是 PC 演示还是车载闭环 |

建议为基础可演示版预留 **1-2 周日历时间**，含失败排查和组员时间协调。视觉不要进入第一阶段的关键路径。

以后采用任何 MCP/Skill 的最小验收：固定提交/版本及依赖；先读实际安装和工具实现；离线检查工具列表与拒绝路径；确认没有自启动串口/自动刷新固件；在明确物理条件下测试开关串口与复位；上传和日志采集不能争抢端口；记录退出时是否释放资源；才能允许受控运动测试。

停止测试应含：启动默认停止、重复命令、超长/未知命令、串口断开、重新连接、无效测距、脱线、模式中途切换。试验次数、路线长度、速度档和光照记录在测试表中；数据没采到就留空，不能先填一个“预期成功率”。

## 10. 许可、归档与采用状态

GitHub 可公开访问不等于所有内容都允许复制、改名、商用或重新授权。记录许可证、固定 SHA、改动文件和来源；复用开源代码与引用设计思想分开标注。根许可证无法识别时阅读实际文件；只有一句许可声明但缺正文的候选，在复制前补齐核对。[^13]

Freenove 根许可已单独保留，不能把派生文件统一贴成 MIT。GPL/AGPL 工具、库与独立进程的集成方式不同；本项目目前未做新的源代码混合或发布许可承诺，实际导入时再逐项核对相容性。Serial Studio Pro-only 模块、视觉模型权重和数据集也要分别处理。

**本轮已完成**：检索采集、45 项对比、关键入口检查、AutoRC 主线核对、COM5 只读枚举、CLI 调试能力检查、USB 程序重新编译、报告与日志归档。

**尚未完成/未执行**：安装候选 MCP/Skill、创建串口适配器、导入新库、实现自主状态机、串口读写、烧录、摄像头/语音接入、实物运动测试。推荐路线不等于已经采用的依赖。

## 来源

45 项仓库链接见各表；精确提交、README/许可证路径与哈希见 [review-metadata](../research/review-metadata-2026-09-13.json)，关键源码定位见 [source-audit](../research/source-audit-2026-09-13.md)。外部页面均于 2026-09-13 Toronto 核对，版本信息以固定提交优先。

[^1]: Arduino，[CLI 官方文档](https://docs.arduino.cc/arduino-cli/)及 [Integration options](https://docs.arduino.cc/arduino-cli/integration-options)，说明命令行、gRPC、嵌入方式以及 IDE 对 CLI 的使用。
[^2]: pySerial，[API 文档](https://pyserial.readthedocs.io/en/latest/pyserial_api.html)，Serial 构造、open、timeout、DTR/RTS；尤其驱动可能在开端口时改变控制线的说明。
[^3]: Model Context Protocol，[Tool Annotations as Risk Vocabulary](https://blog.modelcontextprotocol.io/posts/2026-03-16-tool-annotations/)，说明 annotations 是提示，不是可信强制执行机制。
[^4]: Serial Studio，[固定提交 LICENSE](https://github.com/Serial-Studio/Serial-Studio/blob/5e8c86a13250396beada5bcb07e94609b529eea1/LICENSE.md)、[Pro-vs-Free](https://github.com/Serial-Studio/Serial-Studio/blob/5e8c86a13250396beada5bcb07e94609b529eea1/doc/help/Pro-vs-Free.md)及 [README](https://github.com/Serial-Studio/Serial-Studio/blob/5e8c86a13250396beada5bcb07e94609b529eea1/README.md)。
[^5]: Wokwi，[AVR8js](https://github.com/wokwi/avr8js) 与 [Wokwi CI 官方说明](https://docs.wokwi.com/wokwi-ci/getting-started)。模拟内核与托管服务分开评估。
[^6]: PlatformIO，[Test Runner](https://docs.platformio.org/en/stable/advanced/unit-testing/runner.html)；候选 MCP 的 profiles.ts/build.ts 具体路径见源码检查。
[^7]: Benoit Blanchon，[ArduinoJson 6 到 7 迁移说明](https://arduinojson.org/v7/how-to/upgrade-from-v6/)；TaskScheduler README 和原厂源码分别支持调度与阻塞行为分析。
[^8]: Freenove，[固定循迹实现](https://github.com/Freenove/Freenove_4WD_Car_Kit/blob/a035ca380a9218d0a88aab635a58b9a3c738940f/Sketches/03.2_Automatic_Tracking_Line/03.2_Automatic_Tracking_Line.ino)及同目录头文件；本项目 vendor 保持相同字节。
[^9]: Open Robotics，[ROS Noetic EOL 官方说明](https://www.ros.org/blog/noetic-eol/)；micro-ROS 板型以其仓库固定版本 Supported boards 表为准。
[^10]: AutoRC，[lane_detector.py](https://github.com/Shengqinchu/AutoRC/blob/90340e608afd63ca1e6900db1cd9813bbdd24ca9/current/core/lane_detector.py) 和 [yolo_server.py](https://github.com/Shengqinchu/AutoRC/blob/90340e608afd63ca1e6900db1cd9813bbdd24ca9/current/pc/yolo_server.py)，私有链接需仓库权限。代码未执行、旧仓库未修改。
[^11]: OpenCV，[ArUco 检测教程](https://docs.opencv.org/5.0/tutorials/objdetect/aruco_detection/aruco_detection.html)及 [Board 位姿说明](https://docs.opencv.org/5.0/tutorials/objdetect/aruco_board_detection/aruco_board_detection.html)。实施时需按选定 OpenCV 包版本核对 API，不混用不同版本教程。
[^12]: Arduino，[Uno Rev3 硬件资料](https://docs.arduino.cc/hardware/uno-rev3/)；本项目 CLI 编译报告进一步给出实际可用 Flash 和静态 RAM 占用。
[^13]: GitHub，[Licensing a repository](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)；实际采用仍以源文件和许可证正文为准。
[^14]: Wokwi，[官方 MCP 支持](https://docs.wokwi.com/wokwi-ci/mcp-support) 与 [CI 额度/架构](https://docs.wokwi.com/wokwi-ci/getting-started)。
