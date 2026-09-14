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

## 官方资料

- [装配与烧录顺序](https://docs.freenove.com/projects/fnk0041/en/latest/fnk0041/codes/tutorial/0_Software,_Assembly_and_Play.html)
- [固定版本教程 PDF](https://github.com/Freenove/Freenove_4WD_Car_Kit/blob/a035ca380a9218d0a88aab635a58b9a3c738940f/Tutorial.pdf)
- [电池说明](https://github.com/Freenove/Freenove_4WD_Car_Kit/blob/a035ca380a9218d0a88aab635a58b9a3c738940f/About_Battery.pdf)
- [Arduino CLI 官方文档](https://docs.arduino.cc/arduino-cli/)

完整原厂手册另外保存在本机 `reference/`，不随仓库重复上传。课程资料仍留在上级课程归档中。
