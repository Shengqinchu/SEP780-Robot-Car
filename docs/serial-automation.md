# USB 串口自动调试

本阶段已实现电脑端工具，不等于已经烧录或通过实车测试。真正打开串口前，必须确认裸主控板仅接 USB、电池盒断开、蓝牙移除且执行器隔离。开关串口可能触发复位；即使设置 DTR/RTS 为 inactive，也不能保证驱动不产生跳变。[pySerial 官方说明](https://pyserial.readthedocs.io/en/latest/pyserial_api.html#serial.Serial.open)

## 安装与离线验证

PowerShell 7、Python 3.10+。当前 Windows 实测 Python 3.12.14。虚拟环境保存在项目 `.local/host-pyserial-3.5`，不使用全局 Python 包；依赖固定 `pyserial==3.5`，安装时校验 wheel SHA-256。没有新增 Arduino 库、MCP 或后台服务。

```powershell
./scripts/Setup-Host.ps1
./tests/Test-Host.ps1
./scripts/Serial.ps1 -Action self-test
./scripts/Serial.ps1 -Action list
```

如果 `python` 指向 Windows 应用商店别名或未安装，先提供真实 Python 路径给 `Setup-Host.ps1 -PythonPath`。本机打包应用的 AppData 重定向曾导致 pip 报 WinError 17；项目内 `.local` 环境已安装成功，不需重装系统 Python。

`self-test` 只使用 pySerial 的内存 `loop://`，不是向 Arduino 发送数据；`list` 只枚举系统串口，省略设备序列号和完整硬件实例 ID。当前读取到 COM5 / USB-SERIAL CH340，不是从该名称独立确认了 MCU 型号。

## 已确认隔离之后

每次先重新核对串口。下面命令会覆盖固件或打开端口，只能在确认的物理条件下执行，确认参数不是对物理检查的替代。

```powershell
./scripts/List-Boards.ps1
$port = Read-Host '输入核对后的实际 USB 串口'
./scripts/Upload.ps1 -Program usb_check -Port $port -ConfirmHardwareReady
./scripts/Serial.ps1 -Action usb-check -Port $port -Seconds 8 -ConfirmUsbIsolated
```

`usb-check` 使用 115200 波特率，一次打开/关闭一个会话；看到当前检查固件的 READY 或心跳后，等待至少一秒，再发送一次 `?`。只有至少两条推进的心跳及发送后的精确应答，才报告 passed。READY 可能因固件已经运行而未出现，这本身不会使测试失败。期间出现复位迹象、没有应答、超时或达到字节上限均不会当成通过。

这验证的是检查固件的串口表现，不是 USB 桥对应 MCU 的身份认证，也不证明板载 LED 物理可见、电机/舵机/传感器或电池正常。LED 现象另由现场观察。

只采集、不发送查询：

```powershell
./scripts/Serial.ps1 -Action capture -Port $port -Seconds 8 -MaxBytes 8192 -ConfirmUsbIsolated
```

当前工具只用于 USB 检查阶段，固定 115200 波特率；原厂 9600 波特率示例尚未通过此工具适配。不能将其直接用于运动固件或未隔离的整车。

## 输出与退出

- 标准输出为 JSON，供 Codex/脚本解析，不依赖 IDE 窗口。
- 实物会话的原始 RX/TX 十六进制、相对时间及事件保存在 `artifacts/local/serial-*.jsonl`，摘要在同名 `.json`。文件名含时间和随机后缀，不覆盖已有记录。
- 默认采集窗口 8 秒，可设 1-60 秒；默认最多 8192 接收字节，可设 128-65536。单行缓冲限制 128 字节；超长行丢弃到下一个换行后恢复。
- 窗口约束的是采集循环；串口驱动打开/关闭和磁盘 I/O 时间另计。读超时 50 ms、写超时 500 ms，不调用可能无限等候的 flush。
- `passed` 或按时结束的 `captured` 返回成功；capture 成功只代表采集结束，空日志不代表设备健康。超时、byte_limit、复位、错误和中断返回非零。
- 原始记录一律被 Git 忽略。只把核对过、去除个人信息的摘要和真实结论写入 DEVLOG/共享 artifacts。

## 端口所有权

Python 串口会话和现有 PowerShell Upload 共用 `.local/port-locks` 的独占创建锁。端口规范化后做 SHA-256 命名，COM5 与 com5 是同一把锁；上传先取得锁再编译/上传，串口会话退出或异常时释放自己持有的锁。

若进程被强杀而留下锁，工具会拒绝继续，不自动删锁、杀进程或重试。先确认记录中的 PID/操作者确已结束，关闭 IDE/其他串口软件，再人工处理确实过期的那个锁。不能因为锁文件存在就直接删整个 `.local`。

这是本项目协作锁，不是跨所有软件的系统强制锁；IDE、其他项目及直接调用底层 CLI 不参与。Windows 驱动仍负责实际串口独占，Linux 额外设置 pySerial exclusive。收到 busy/access denied 先排查占用者，不强制抢占。

## 测试覆盖与当前状态

42 个 Python 测试覆盖参数门槛、URL/非法端口拒绝、分包/超长行、精确应答、旧应答排除、时间回绕/复位、未知固件不写入、超时/字节预算、断线/中断清理、锁冲突、结果落档和软件回环。PowerShell 另验证锁命名与 Python 一致、锁互斥以及非法端口拒绝。

Windows 本机和 [GitHub Linux CI](https://github.com/Shengqinchu/SEP780-Robot-Car/actions/runs/34796061715) 均通过 42 项测试、软件回环及 30/30 无上传编译；测试代码提交为 `852beb0`。当前未开真实串口、未烧录、未测试执行器；下一步等待现场隔离状态确认。
