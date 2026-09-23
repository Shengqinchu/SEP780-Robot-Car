# 录像 Demo 中英对照逐字稿

[演示执行手册](demo-guide.md) | [Demo procedure](demo-guide.en.md) | [返回 README](../README.md)

这是录像版逐字稿，不是现场即兴演讲稿。建议成片约 3 分 50 秒；这只是制作目标，不是课程官方时限。中文和英文内容逐段对应。最终视频选择一种语言完整录制，不要一句中文一句英文交替。

## 逐字稿

| 时间 | 画面与动作 | 中文逐字稿 | English script |
| --- | --- | --- | --- |
| 0:00-0:08 | 标题页后切到小车全景。 | 大家好。这是我们的 SEP 780 智能小车项目。 | Hello. This is our SEP 780 smart robot car project. |
| 0:08-0:18 | 缓慢拍摄整车。 | 小车基于 Freenove FNK0041 四驱平台。我们保留了原厂硬件。 | The car is based on the Freenove FNK0041 four-wheel platform. We kept the original hardware. |
| 0:18-0:32 | 近拍主控、电机和传感器，可加简单文字标注。 | 它有一块 Arduino 兼容主控板和四个直流电机。它还有三路红外循迹传感器、一个超声波传感器、一个蜂鸣器和一个 BLE 模块。 | It has an Arduino-compatible control board and four DC motors. It also has three infrared line sensors, an ultrasonic sensor, a buzzer, and a BLE module. |
| 0:32-0:45 | 回到小车和路线全景。 | 我们开发了新的集成控制系统。小车可以循迹、检测障碍、安全停车，并在路线恢复后继续行驶。 | We developed a new integrated control system. The car can follow a line, detect an obstacle, stop safely, and continue when the path is clear. |
| 0:45-0:56 | 画面显示小车静止，叠加安全关键词。 | 如果线路丢失、传感器失效、电池电压过低或连接超时，小车也会停车。 | The car also stops if it loses the line, gets invalid sensor data, detects low voltage, or loses the connection. |
| 0:56-1:08 | 手机 App 全屏近景。 | 这是我们自己开发的 Android App。我们使用原生 Java 和 Android SDK 完成了它。 | This is the Android app developed by our team. We built it with native Java and the Android SDK. |
| 1:08-1:20 | 镜头对准蓝牙状态和语音按钮。 | App 使用 Bluetooth Low Energy，也就是 BLE GATT，与小车通信。它使用 Android 系统的 SpeechRecognizer 识别中英文语音命令。 | The app uses Bluetooth Low Energy, or BLE GATT, to communicate with the car. It uses Android's SpeechRecognizer for Chinese and English voice commands. |
| 1:20-1:31 | 指向顶部语言和蓝牙区域。 | 顶部可以切换中文和英文。蓝色蓝牙指示灯表示小车已经连接。 | We can select Chinese or English at the top. The blue Bluetooth light shows that the car is connected. |
| 1:31-1:43 | 指向三个数据指标。 | 这三个数值显示电池电压、前方距离和三路循迹状态。 | These three values show battery voltage, front distance, and the line sensor state. |
| 1:43-1:57 | 指向赛车摇杆和速度上限滑杆；小车保持架空或停止。短按住鸣笛再松开，并指向语音、循迹和停止。 | 中间的摇杆同时控制前后和转向。可选速度上限是 110 到 180，默认是 150。松手会停车。循迹使用车端固定参数，不受这个滑杆影响。我们也可以长按按钮手动鸣笛。 | The center joystick controls throttle and steering together. The selectable speed limit is 110 to 180, with 150 as the default. Releasing the stick stops the car. Line following uses fixed vehicle settings and does not use this slider. We can also hold a button to sound the horn. |
| 1:57-2:07 | 小车上电，App 显示已连接和 `0/0`。 | 小车上电后保持停止。现在左右输出都是零。 | The car stays stopped after power-up. Both requested outputs are now zero. |
| 2:07-2:21 | 把车放在空旷直线。点击语音按钮，等界面显示正在听，再说命令。 | 现在我说：“前进。”小车运行大约一秒，然后自动停止。 | Now I say, “Forward.” The car moves for about one second. Then it stops automatically. |
| 2:21-2:35 | 把中间探头对准黑线。点击语音并说命令。保持路线全景。 | 现在我说：“开始循迹。”小车用短驱动和短滑行脉冲沿黑线移动。三个传感器不断调整左右轮输出。 | Now I say, “Follow line.” The car follows the black line with short drive and coast pulses. The three sensors keep adjusting the left and right outputs. |
| 2:35-2:49 | 小车进入直线障碍区。不要用手挡；使用固定纸板。 | 当前方障碍进入二十厘米范围时，小车停车，蜂鸣器发出提示音。它不会盲目绕行。 | When an obstacle comes within twenty centimeters, the car stops and the buzzer gives a warning. It does not make a blind turn around the obstacle. |
| 2:49-3:02 | 等车完全停稳，再把纸板移到 30 cm 外。 | 现在我们把障碍移到三十厘米以外。控制器检查稳定的距离和线路信号。至少等待零点六秒后，小车继续循迹。 | Now we move the obstacle more than thirty centimeters away. The controller checks for stable range and line data. After at least zero point six seconds, the car continues. |
| 3:02-3:14 | 可选镜头：在直线前方用白卡暂时盖住黑线，停稳后移开。 | 我们暂时盖住黑线。小车找不到有效线路，所以它停车。线路恢复后，它继续行驶。 | We cover the black line for a moment. The car cannot find a valid line, so it stops. It continues when the line returns. |
| 3:14-3:25 | 点击语音，清楚说停止；手机和小车同框。 | 最后，我说：“停止。”小车立即停止。左右输出回到零。 | Finally, I say, “Stop.” The car stops. Both requested outputs return to zero. |
| 3:25-3:40 | 显示测试界面、运行表或 GitHub 仓库，不显示个人信息。 | 我们用单元测试和传感器场景回放检查同一套 C++ 控制逻辑。我们也在同一条实体路线上重复测试，并记录每次结果。 | We check the same C++ control logic with unit tests and sensor scenario replay. We also repeat the same physical route and record every result. |
| 3:40-3:50 | 最终全景和项目名称。 | 这个项目结合了自主控制、安全保护、语音操作和可重复测试。感谢观看。 | This project combines autonomous control, safety protection, voice control, and repeatable testing. Thank you for watching. |

## 没完成五次路线前的替换句

只有完成并记录至少五次固定路线后，才能使用“我们也在同一条实体路线上重复测试，并记录每次结果”。尚未完成时，替换为：

| 中文 | English |
| --- | --- |
| 我们已经固定了测试路线和记录方法。下一步是在同一条路线上完成五次测试，并记录成功和失败条件。 | We have fixed the test route and the recording method. Our next step is to complete five runs on the same route and record both success and failure conditions. |

## 录像方法

1. 使用横屏 1080p、30 fps 和固定支架。主镜头从上电前开始，连续拍到最终停止，不用剪辑掩盖失败。
2. 主镜头要同时看到整条路线、小车、障碍和操作员的手。不要让相机或三脚架进入超声波视野。
3. App 近景可以用第二台手机拍摄，或使用安卓屏幕录制后做画中画。录屏前关闭通知，避免显示个人信息。
4. 旁白可以后期单独录制，但“前进 / Forward”“开始循迹 / Follow line”和“停止 / Stop”三个实际语音命令要保留现场原声。
5. 说语音命令前先点击“语音命令”，等界面显示“正在听 / Listening”。命令期间不要放背景音乐，也不要让其他人说话。
6. 主录像只选择一种语言。另一种语言用同一份对照稿另录旁白，或作为字幕；不要在已连接状态切换界面语言，因为 App 会安全停止并断开 BLE。
7. 片头只放项目名、课程号和组员姓名。片尾可放 GitHub 地址和测试结果，不放冗长声明。

## 剪辑顺序

```text
标题 -> 硬件 -> 项目目标 -> App 屏幕 -> 安全启动
     -> 语音前进 -> 语音循迹 -> 障碍停车/恢复
     -> 可选脱线测试 -> 语音停止 -> 测试证据 -> 结束
```

可选脱线镜头如果还没有稳定通过，可以直接删除；不要为了凑功能在录像当天临时修改程序。其他核心镜头尽量来自同一次连续运行。
