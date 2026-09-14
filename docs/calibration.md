# 电池到货后的校准

[English](calibration.en.md) | [返回 README](../README.md)

按顺序完成下列步骤。一次只改一个参数，每次测试记录固件提交、参数、场地和现象。准备直尺、浅色测试板、套件黑胶带，以及能架空四轮的稳固支撑。

## 1. 建立原厂硬件基线

先按[装配与上电检查](bring-up.md)核对电池极性、插头和开关。断电插拔线材，上传前移除蓝牙。首次通电架空四轮，留出超声波转头活动空间，确保能随时关闭车上电源。

1. 上传原厂 `servo_center`，实际观察归中，断电后固定转头朝正前。
2. 上传原厂 `motor_test`，确认四个轮子的前进/后退方向一致；该示例会自动重复动作。
3. 用 `tracking_sensor` 检查三路黑线/浅色底读数；左、中、右分别遮盖，不仅检查组合值。
4. 用原厂 `ultrasonic_test` 检查测距，该示例会扫动舵机。摆放平整、能反射声波的目标。

原厂读数异常时先处理接线、供电、安装位置，再上传项目固件。不要同时改软件算法来补偿未确认的接线问题。

## 2. 上传项目固件

`robot_car` 启动会将舵机转到配置的中位，但不会自动启动车轮。轮子继续架空，先确认转头不会顶住结构。关闭车板 POWER 后按原厂流程上传，完成后再接入正确的电池供电并开启车板。

```powershell
./scripts/List-Boards.ps1
$port = Read-Host '输入刚确认的小车串口'
./scripts/Upload.ps1 -Program robot_car -Port $port -ConfirmHardwareReady
./scripts/Robot.ps1 -Action observe -Port $port -Seconds 10 -ConfirmHardwareReady
```

`observe` 不发送指令。它记录 `line`、`range_mm`、`battery_mv`、当前模式和左右轮 PWM。打开串口可能复位主控，因此即使只观察也要留出舵机活动空间。不要与 IDE 串口监视器同时占用端口。

## 3. 校准读数和方向

参数集中在 [config.h](../firmware/robot_car/config.h)。修改后重新编译、测试并显式上传。

| 项目 | 方法 | 修改位置 |
| --- | --- | --- |
| 舵机中位 | 确认标称 90 度时超声波朝正前，优先调整舵盘安装 | `hardware::servo_center_degrees` |
| 电池电压 | 将遥测与万用表电池端电压比较；偏差明显先检查接线与分压 | `hardware::adc_full_scale_mv`，默认 20000 |
| 黑白极性 | 官方默认黑线为 1；分别验证三路 | `hardware::black_reads_high` |
| 左右电机方向 | 在架空状态短时间驱动，确认左右逻辑正值均为前进 | `hardware::invert_left_motor` / `invert_right_motor` |
| 左右轮偏差 | 低速短直线，多次观察偏向，再小幅调整 | `left_trim_pwm` / `right_trim_pwm` |

前方需有约 30 cm 到 4 m 范围内的有效回波才允许启动。没有回波时 `range_mm=0`，程序会停车，不把它当作“前方无限远”。电池默认工作检查范围为 6.6 V 到 9.0 V；它是软件检查值，不代替电芯保护或充电器。

先发送 1 秒、低 PWM 的架空动作：

```powershell
./scripts/Robot.ps1 -Action drive -Port $port -Left 70 -Right 70 -Seconds 1 -ConfirmHardwareReady -ConfirmMotionClear
./scripts/Robot.ps1 -Action stop -Port $port -ConfirmHardwareReady
```

输出太小导致轮子不动时，先核对电池、插头和电机方向，再逐步调整。首次地面测试同样从低速、短时间开始。

## 4. 调整循迹与遇障行为

在浅色平面贴单条黑线，先直线，再增加宽缓弯道，避免阳光直射循迹传感器。

| 参数 | 初始值 | 校准重点 |
| --- | --- | --- |
| `cruise_pwm` | 90 | 能稳定起步且不容易冲出弯道 |
| `turn_reduction_pwm` | 50 | 两侧同时看到线时的转向幅度 |
| `max_pwm` | 150 | 逻辑输出上限，不是实际速度单位 |
| `obstacle_stop_mm` | 200 | 加上测距误差和实际滑行距离后仍能停在目标前 |
| `obstacle_resume_mm` | 300 | 大于停车阈值，避免边缘反复启停 |
| `clear_hold_ms` | 600 | 需连续清晰回波并至少有三次不同采样才能恢复 |
| `line_lost_ms` | 400 | 脱线始终立即零输出；超过该时间需重新启动 |

使用红外遥控器：`1` 启动循迹，`0` 或电源键停车。手动先按 `2`，按住方向键移动；释放后手动指令在默认 350 ms 后过期。切换模式先停车。

电脑控制采用限时会话：

```powershell
./scripts/Robot.ps1 -Action line -Port $port -Seconds 5 -ConfirmHardwareReady -ConfirmMotionClear
```

电脑会话结束或发生错误时发送 STOP；电脑断开后，串口拥有的循迹模式由 1200 ms 指令超时停止。红外启动的循迹可脱离电脑持续运行。地面运动不要拖拽或缠绕 USB 线，独立运行优先使用红外遥控。

这版只做前方障碍停车与恢复，不规划绕行。手动模式的前向障碍保护会停止所有运动，包含倒车；没有后方/侧方传感器。停止是将 PWM 设为 0，不是保证机械上瞬间刹停。

## 5. 记录和复测

按[验证清单](test-plan.md)每项至少重复五次，记录成功次数、失败条件、距离和是否发生异常复位。未执行的项目留空或写“未执行”。

原始记录保存到 `artifacts/local/robot-*.jsonl`。选定一次会话后导出 CSV：

```powershell
. ./scripts/Common.ps1
$trace = Read-Host '输入要导出的 robot JSONL 路径'
& (Get-HostPython) -X utf8 ./host/export_telemetry.py $trace ./artifacts/local/calibration.csv
```

使用[实测记录模板](templates/hardware-test.md)整理一次测试，再将真实发现与参数修改追加到 [DEVLOG.md](../DEVLOG.md)。固定最终参数后重复相同路线，比较原厂与项目固件。
