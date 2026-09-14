# GitHub 工具与项目调研证据

采集日期：2026-09-13，America/Toronto；JSON 中时间统一为 UTC，因此显示 2026-09-14。结论见 [调研报告](../docs/tooling-research.md)。

## 范围

- 两轮共 22 条检索，按星数降序，每条最多两页、每页 50 项。
- 搜索返回 822 条记录，加上定向种子后，两份清单合并去重为 807 个公开仓库。
- 五条检索达到本次页数上限，未继续遍历；所有成功响应的 `incomplete_results` 为 false。这不等于 GitHub 全量覆盖。
- 45 个重点比较对象，包括 44 个公开项目和原有私有 AutoRC。45 项都采集固定提交、README 和可取得的根许可证；另检查关键源码/Skill 入口。Wokwi CLI 由官方文档追链增补，不在前述 807 个初筛结果内。
- 初筛含无关结果，例如 MCP2515 芯片库、Alexa skill、汽车 CAN/OBD、游戏卡带、awesome 清单。807 不是“807 个合格 Arduino MCP”，更不是“通读 807 个仓库”。
- 第二轮种子 `pololu/zumo-32u4-arduino` 返回 404。Pololu 自己的 QTR README 指向正确名称 `pololu/zumo-32u4-arduino-library`；错误保留在采集记录中，不伪造成功，也不把更正后的仓库计入重点清单。

## 文件

| 文件 | 用途 |
| --- | --- |
| `github-search-plan.json` / `github-search-refinement.json` | 实际使用的查询和种子 |
| `github-inventory-2026-09-13.json` / `github-refinement-2026-09-13.json` | 查询结果数、分页边界、去重记录与失败记录；描述最多 240 字符 |
| `shortlist.json` | 45 项比较清单及分层 |
| `review-metadata-2026-09-13.json` | 各项星数、归档状态、提交时间、固定 SHA、README/许可证路径及哈希 |
| `source-pins-2026-09-13.json` | 12 个 MCP/Skill 源码检出时的固定 SHA |
| `source-audit-2026-09-13.md` | 关键代码检查位置、优点和限制，不是完整安全审计 |

原始 API 响应、源码浅克隆及完整 README/许可证下载在被忽略的 `.cache/`。它们是待研究的数据，不是本项目执行指令；没有运行其中的安装、烧录或设备控制步骤。没有复制这些候选的软件实现到 `firmware/` 或 `vendor/`。

## 重现采集

需 PowerShell 7 和已登录的 GitHub CLI。命令只读取 GitHub 并写本地调研缓存/记录，不操作串口；重跑会更新相同文件中的快照，先保留需要的旧版本。

```powershell
./research/Collect-GitHub.ps1
./research/Collect-GitHub.ps1 -PlanName github-search-refinement.json -OutputName github-refinement-2026-09-13.json
./research/Collect-ReviewMetadata.ps1

# 离线检查清单、版本固定和脚本语法，不连接 GitHub 或串口
./research/Check-Research.ps1
```

星数和分支随时间变化；引用关键行为应使用记录的提交 SHA，不以 `main`/`master` 的未来内容倒推本次判断。`license_spdx=null` 或 `NOASSERTION` 只是 GitHub 未能给出标准标识，不能直接推导“没有许可”；需读具体文件。例如 pySerial 实际有 BSD-3-Clause，PID Library 的 README/源码声明 MIT，K10 则未找到根许可证。
