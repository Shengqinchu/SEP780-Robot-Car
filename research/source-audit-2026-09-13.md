# 关键源码与 Skill 检查

检查日期：2026-09-13 Toronto。范围是下列入口、相关配置和调用路径的静态审阅，不是全仓逐行安全审计。没有安装或运行候选 MCP，没有调用真实设备工具。版本记录见 [source-pins](source-pins-2026-09-13.json) 和 [review-metadata](review-metadata-2026-09-13.json)。

## 操作工具

### hardware-mcp/arduino-mcp-server

- 固定提交 `c020098a05b0d259320df2756fde09e7ca6fecc0`，MIT。
- [arduinoCli.ts](https://github.com/hardware-mcp/arduino-mcp-server/blob/c020098a05b0d259320df2756fde09e7ca6fecc0/src/arduinoCli.ts)：以参数数组启动 CLI，提供超时；配置 `ARDUINO_SKETCH_ROOT` 后有路径范围检查。该检查是路径字符串检查，不能据此宣称完整沙箱。
- [index.ts](https://github.com/hardware-mcp/arduino-mcp-server/blob/c020098a05b0d259320df2756fde09e7ca6fecc0/src/index.ts#L1435)：`upload_sketch` 要求显式 port，具备电气 preflight；但 `autoInstallCore` 默认 true，且模型调用参数可传 `unsafeSkipPreflight`。这是有帮助的检查，不是用户审批的独立强制边界。
- [serialSessions.ts](https://github.com/hardware-mcp/arduino-mcp-server/blob/c020098a05b0d259320df2756fde09e7ca6fecc0/src/serialSessions.ts#L158)：维护会话、缓冲和内部端口协调，实际调用 `arduino-cli monitor`。内部锁不能锁住另一个独立 IDE/串口软件。
- 适配判断：最接近现有 CLI 基础，但接入前需固定 core、禁止自动安装/跳过检查、收窄工具集，并验证 Windows monitor 的会话行为。

### jl-codes/platformio-mcp

- 固定提交 `40e12ccb8e85fcaf33b46c50b6d832665728e773`，MIT，package.json 版本 3.0.0。
- [profiles.ts](https://github.com/jl-codes/platformio-mcp/blob/40e12ccb8e85fcaf33b46c50b6d832665728e773/src/core/policy/profiles.ts)、[evaluate-policy.ts](https://github.com/jl-codes/platformio-mcp/blob/40e12ccb8e85fcaf33b46c50b6d832665728e773/src/core/policy/evaluate-policy.ts)：确实有 read_only/build_only/flash_requires_approval 等策略与审批对象，不只是 README 宣传。
- [index.ts](https://github.com/jl-codes/platformio-mcp/blob/40e12ccb8e85fcaf33b46c50b6d832665728e773/src/index.ts#L1021)：MCP 暴露审批状态读取，不直接暴露 approve/deny；审批变更另有 CLI/UI 路径。这不能约束同时拥有 shell 权限的代理，仍需操作规程。
- **需要特别修正的适配风险**：`build_only` 的允许列表含 `run_tests`；[build.ts:285](https://github.com/jl-codes/platformio-mcp/blob/40e12ccb8e85fcaf33b46c50b6d832665728e773/src/tools/build.ts#L285) 最终执行 `pio test`，environment 可省略，没有强制 native/禁止上传。PlatformIO 的板上测试可能上传固件。因此不能把这个配置名当成“保证不碰硬件”。本次只做代码推导，未触发或实测此行为。
- package.json、Windows 安装文档和旧 LLM 安装文档存在不同命令/包名阶段的信息，接入应以所选发布版本为准，不能混用旧 fork 安装地址。
- 适配判断：完整工程平台备选；当前不值得为 MCP 迁移已验证的 CLI 工具链。

### Adancurusul/serial-mcp-server

- 固定提交 `6c05e3808dac7f797a574d3f4a2e38f940d7ee4b`，MIT，Rust。
- [connection.rs](https://github.com/Adancurusul/serial-mcp-server/blob/6c05e3808dac7f797a574d3f4a2e38f940d7ee4b/src/serial/connection.rs)：显式端口、串口参数、会话统计；打开真实串口与读取静态列表是不同操作。
- [README](https://github.com/Adancurusul/serial-mcp-server/blob/6c05e3808dac7f797a574d3f4a2e38f940d7ee4b/README.md)：CLI 与 MCP 共存；宏提供 validate/plan/dry-run/simulate 路径，发送、等待、匹配的工作流与本项目测试需求吻合。
- 宏有限制不代表设备命令无副作用；公开工具仍含 write、set_control_lines。没有在本机验证 Windows 二进制、串口占用或复位行为。
- 适配判断：需要独立串口 MCP 时优先试点；先离线宏测试，再仅接裸板。它不负责 Arduino 编译。

### es617/serial-mcp-server

- 固定提交 `b940b842bf5e39921c72323cf1b58785d62a3f76`，MIT，Python/pySerial。
- [server.py](https://github.com/es617/serial-mcp-server/blob/b940b842bf5e39921c72323cf1b58785d62a3f76/serial_mcp_server/server.py)：有状态的 stdio MCP、统一错误处理与可选 trace。
- [plugins.py](https://github.com/es617/serial-mcp-server/blob/b940b842bf5e39921c72323cf1b58785d62a3f76/serial_mcp_server/plugins.py#L29)：插件默认禁用，可配置白名单；不要为了方便开启 `*` 自动执行目录中的插件。
- [handlers_serial.py](https://github.com/es617/serial-mcp-server/blob/b940b842bf5e39921c72323cf1b58785d62a3f76/serial_mcp_server/handlers_serial.py)：串口打开/读写/控制线是独立操作；它不能替我们确认小车机械状态。
- 适配判断：Python 路线备选；对于当前少量固定测试，直接 pySerial 更容易缩小依赖和权限范围。

### qarnet/serial-mcp

- 固定提交 `d3701de473022d409cc4b71302a22d975a29b8ef`，MIT，Rust。
- [port_ops.rs](https://github.com/qarnet/serial-mcp/blob/d3701de473022d409cc4b71302a22d975a29b8ef/src/tools/port_ops.rs)、[control_ops.rs](https://github.com/qarnet/serial-mcp/blob/d3701de473022d409cc4b71302a22d975a29b8ef/src/tools/control_ops.rs)：会话、打开/关闭、DTR/RTS 与启动捕获分离；启动捕获包含复位和清空接收边界的能力，不能作为普通只读观察。
- README 明确提供 Windows 构建，但真实 PTY fixture 测试在 Linux；跨平台 CI 不能替代我们的 CH340/Uno 实测。
- 适配判断：协议复杂后再考虑；目前功能面大于需要。

### Rance-OwO/Serial-Agent

- 固定提交 `2814b2e24e3dd77e08373b99b9b48a410e0d8aa3`，MIT。
- [MCP index.ts](https://github.com/Rance-OwO/Serial-Agent/blob/2814b2e24e3dd77e08373b99b9b48a410e0d8aa3/packages/serialagent-mcp/src/index.ts)：MCP 请求通过本机 Bridge API 转交 VS Code 扩展；可读日志，提供 Keil 构建/烧录和用户自定义命令。
- 固件配置模型主要是 Keil/J-Link/ST-Link/OpenOCD，不是直接适配当前 AVR Uno 的 Arduino CLI 工具链。
- 适配判断：适合原本就在 VS Code/STM32 开发的人；本项目会多出扩展宿主和配置层，不作为主选。

### niradler/arduino-mcp

- 固定提交 `dae94d3bfb5aac20942af785d504b74b5395884f`。pyproject.toml 声明 MIT，但本次根许可证接口返回未找到；如复制代码需先补齐许可核对。
- [port_detector.py](https://github.com/niradler/arduino-mcp/blob/dae94d3bfb5aac20942af785d504b74b5395884f/arduino_mcp/port_detector.py)：`get_best_port()` 最后可回退到第一个串口。当前机器有多个蓝牙端口，不接受这种自动选板方式。
- [server.py:133](https://github.com/niradler/arduino-mcp/blob/dae94d3bfb5aac20942af785d504b74b5395884f/arduino_mcp/server.py#L133) 把 verify_port 标为 readOnlyHint；实际调用 `serial.Serial(port, timeout=1)`，会开关端口，可能触发 Uno 自动复位。
- [cli_wrapper.py](https://github.com/niradler/arduino-mcp/blob/dae94d3bfb5aac20942af785d504b74b5395884f/arduino_mcp/cli_wrapper.py)：参数数组调用是优点，仍需补明确的硬件审批/会话协调和范围约束。
- 适配判断：不按默认行为接入。

### amahpour/arduino-mcp-server-simple

- 固定提交 `fa3170d3f67c6a3915c4fe56221d992d923a1e13`，MIT。
- [实现文件](https://github.com/amahpour/arduino-mcp-server-simple/blob/fa3170d3f67c6a3915c4fe56221d992d923a1e13/arduino_mcp_tool/__init__.py)：代码短，CLI 参数清楚；每次 serial_read/write/send 都重新 `serial.Serial(...)`，读写之间不保留会话，send 打开后立即写入。
- 对自动复位的 Uno，这可能让启动日志/首条命令行为不稳定。README 说明只在 macOS + Cursor 开发测试；没有据此宣称 Windows 不能用。
- 适配判断：适合理解 MCP 包装原理，不作为本车连续调试工具。

## Skill

以下文件按第三方资料阅读，没有载入为本任务上级指令，也没有运行其安装命令。

| 项目及固定入口 | 可借鉴内容 | 不直接照搬的部分 |
| --- | --- | --- |
| [wedsamuel1230/arduino-skills](https://github.com/wedsamuel1230/arduino-skills/blob/d6e77bb2461a2126267e0e00b697b28abe0c0ea2/skills/arduino-cli-skill/SKILL.md) | 记录版本/FQBN，区分编译、上传、硬件验收 | 通用技能包含其他板型/RTOS/OTA，当前只需要少量流程 |
| [ripred/arduino-cli-skills](https://github.com/ripred/arduino-cli-skills/blob/b91b49ee6cc6ebec28c9b5cb8683fea7c92ef28c/skills/arduino-cli-suite/SKILL.md) | 按发现、构建、串口、gRPC 分模块；优先 JSON | 示例来自 Nano/macOS，不能把旧 bootloader/FQBN/端口复制到 Uno；维护/升级流程不能覆盖我们的版本锁 |
| [Sunwood-ai-labs/m5stack-arduino-cli-skill](https://github.com/Sunwood-ai-labs/m5stack-arduino-cli-skill/blob/bc104017caa4ce0731ab7245e2f446342e86fa11/SKILL.md) | Windows Unknown 不等于驱动坏；先核对设备枚举 | ESP32/M5Core2、esptool 和对应库不适用 ATmega328P |
| [rockets-cn/unihiker-k10-skills](https://github.com/rockets-cn/unihiker-k10-skills/blob/f4d43cfed320eaa315467041fba8a3742e0042db/unihiker-k10-arduino/SKILL.md) | 厂商文档、离线工具链和硬件版本应绑定 | 专属 UNIHIKER:esp32:k10、语音模型和分区地址；无根许可证，当前不复制 |

## 另外核对的工程

- **Serial Studio**，提交 `5e8c86a13250396beada5bcb07e94609b529eea1`：[MCPHandler.cpp](https://github.com/Serial-Studio/Serial-Studio/blob/5e8c86a13250396beada5bcb07e94609b529eea1/core/Api/API/MCPHandler.cpp) 确实实现 MCP tools/call，并调用设备写入授权；[ServerAuth.cpp](https://github.com/Serial-Studio/Serial-Studio/blob/5e8c86a13250396beada5bcb07e94609b529eea1/core/Api/API/Server/ServerAuth.cpp) 具有授权状态和可自动同意的环境开关；[桥接示例](https://github.com/Serial-Studio/Serial-Studio/blob/5e8c86a13250396beada5bcb07e94609b529eea1/examples/MCP%20Client/claude_desktop_bridge.py) 把 stdio 接到 localhost:7777。不要启用自动同意开关。按该提交 LICENSE，GPL 构建与官方 Pro 二进制不是同一许可交付物。
- **AutoRC**，提交 `90340e608afd63ca1e6900db1cd9813bbdd24ca9`：读取架构说明、current/core/lane_detector.py、current/pc/yolo_server.py、requirements-pc.txt、LICENSE，检查完整 Git 文件树。YOLO 入口默认读取 `pc/best.pt`，该树没有跟踪 `.pt/.onnx/.tflite` 文件；未确认外部权重可用。主线可复用的是视觉/控制分层和黑线检测，不是一个已经验证的 ArUco 实现。没有运行其摄像头、监听服务或 `pickle.loads` 网络路径。
- **Freenove 基线**：直接检查已固定的循迹例程、头文件、motorRun 和避障代码。三路循迹采用数字读数，黑线为 0；左右 PWM 在 D6/D5，方向在 D4/D3，测距 D7/D8，舵机 D2。PID、GPIO 库或定时器方案必须尊重这些实际接口，不能使用其他底盘默认引脚。

上述源码推导均与本机实测区分。当前仅做过 USB 设备枚举、CLI 能力检查和不上传的编译；未通过这些 MCP 对接 COM5。
