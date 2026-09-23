[CmdletBinding()]
param()
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/Common.ps1')

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$manifest = Get-Content -LiteralPath (Join-Path $ProjectRoot 'vendor/freenove-manifest.json') -Raw | ConvertFrom-Json
Assert-Condition ($manifest.commit -eq $Toolchain.upstream.commit) 'Upstream commit mismatch.'
$vendor = Join-Path $ProjectRoot 'vendor/freenove'
$actualFiles = @(Get-ChildItem -LiteralPath $vendor -File -Recurse)
Assert-Condition ($actualFiles.Count -eq $manifest.files.Count) 'Unexpected vendor file count.'
foreach ($file in $manifest.files) {
    Assert-Condition (-not ($file.path -match '(^/)|(^|/)\.\.(/|$)|:')) "Invalid manifest path: $($file.path)"
    $path = Join-Path $vendor $file.path
    Assert-Condition (Test-Path -LiteralPath $path -PathType Leaf) "Missing vendor file: $($file.path)"
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-Condition ($hash -eq $file.sha256) "Modified vendor file: $($file.path)"
}
Write-Host "PASS: $($manifest.files.Count) original vendor files match SHA-256."

$native = Get-Content -LiteralPath (Join-Path $ProjectRoot 'native.lock.json') -Raw | ConvertFrom-Json
$unityRoot = Join-Path $ProjectRoot 'vendor/unity'
Assert-Condition (@(Get-ChildItem -LiteralPath $unityRoot -File -Recurse).Count -eq $native.unity.files.Count) 'Unexpected Unity file count.'
foreach ($file in $native.unity.files) {
    $path = Join-Path $unityRoot $file.path
    Assert-Condition ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq $file.sha256) "Modified Unity source: $($file.path)"
}
Write-Host 'PASS: Pinned Unity source hashes.'

$programs = @(Get-Content -LiteralPath (Join-Path $ProjectRoot 'programs.json') -Raw | ConvertFrom-Json)
Assert-Condition (@($programs.name | Select-Object -Unique).Count -eq $programs.Count) 'Duplicate program name.'
foreach ($program in $programs) {
    Assert-Condition (-not ($program.path -match '(^/)|(^|/)\.\.(/|$)|:')) 'Program paths must be repository-relative.'
    $folder = Join-Path $ProjectRoot $program.path
    $sketchName = Split-Path $folder -Leaf
    Assert-Condition (Test-Path -LiteralPath (Join-Path $folder ($sketchName + '.ino'))) "Missing sketch: $($program.name)"
    Assert-Condition ($program.actuators -is [bool]) 'Actuator flags must be booleans.'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($program.power)) 'Missing power-state requirement.'
}
Assert-Condition ((Get-Program 'servo_center').actuators -eq $true) 'Servo program must be marked as actuating.'
Assert-Condition ((Get-Program 'servo_check').actuators -eq $true) 'Servo diagnostic moves on boot or reset and must be marked as actuating.'
Assert-Condition ((Get-Program 'motor_check').actuators -eq $true) 'Motor diagnostic moves on boot or reset and must be marked as actuating.'
Assert-Condition ((Get-Program 'ultrasonic_test').actuators -eq $true) 'Ultrasonic example sweeps the servo.'
Assert-Condition ((Get-Program 'motor_test').actuators -eq $true) 'Motor program must be marked as actuating.'
Assert-Condition ((Get-Program 'robot_car').actuators -eq $true) 'Robot controller centers the head and can drive.'
Write-Host "PASS: $($programs.Count) named programs and actuator warnings."

foreach ($script in Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'scripts'), $PSScriptRoot -Filter '*.ps1' -File) {
    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$parseErrors)
    Assert-Condition ($parseErrors.Count -eq 0) "PowerShell syntax errors: $($script.Name)"
}
Write-Host 'PASS: PowerShell script syntax.'

$androidLock = Get-Content -LiteralPath (Join-Path $ProjectRoot 'android-toolchain.lock.json') -Raw | ConvertFrom-Json
$androidBuild = Get-Content -LiteralPath (Join-Path $ProjectRoot 'mobile/android/app/build.gradle.kts') -Raw
$androidRootBuild = Get-Content -LiteralPath (Join-Path $ProjectRoot 'mobile/android/build.gradle.kts') -Raw
$androidManifest = Get-Content -LiteralPath (Join-Path $ProjectRoot 'mobile/android/app/src/main/AndroidManifest.xml') -Raw
$androidActivity = Get-Content -LiteralPath (Join-Path $ProjectRoot 'mobile/android/app/src/main/java/io/github/shengqinchu/sep780/MainActivity.java') -Raw
$androidLayout = Get-Content -LiteralPath (Join-Path $ProjectRoot 'mobile/android/app/src/main/res/layout/activity_main.xml') -Raw
$androidJoystick = Get-Content -LiteralPath (Join-Path $ProjectRoot 'mobile/android/app/src/main/java/io/github/shengqinchu/sep780/RaceJoystickView.java') -Raw
$androidMixer = Get-Content -LiteralPath (Join-Path $ProjectRoot 'mobile/android/app/src/main/java/io/github/shengqinchu/sep780/DriveMixer.java') -Raw
$androidStringsEn = Get-Content -LiteralPath (Join-Path $ProjectRoot 'mobile/android/app/src/main/res/values/strings.xml') -Raw
$androidStringsZh = Get-Content -LiteralPath (Join-Path $ProjectRoot 'mobile/android/app/src/main/res/values-zh-rCN/strings.xml') -Raw
$androidLocales = Get-Content -LiteralPath (Join-Path $ProjectRoot 'mobile/android/app/src/main/res/xml/locales_config.xml') -Raw
$bleClient = Get-Content -LiteralPath (Join-Path $ProjectRoot 'mobile/android/app/src/main/java/io/github/shengqinchu/sep780/BleUartClient.java') -Raw
$mobileController = Get-Content -LiteralPath (Join-Path $ProjectRoot 'mobile/android/app/src/main/java/io/github/shengqinchu/sep780/RobotCommandController.java') -Raw
$mobileProtocol = Get-Content -LiteralPath (Join-Path $ProjectRoot 'mobile/android/app/src/main/java/io/github/shengqinchu/sep780/RobotProtocol.java') -Raw
$voiceParser = Get-Content -LiteralPath (Join-Path $ProjectRoot 'mobile/android/app/src/main/java/io/github/shengqinchu/sep780/VoiceCommandParser.java') -Raw
$hostProtocol = Get-Content -LiteralPath (Join-Path $ProjectRoot 'host/robot_protocol.py') -Raw
$robotScript = Get-Content -LiteralPath (Join-Path $ProjectRoot 'scripts/Robot.ps1') -Raw
$robotConfig = Get-Content -LiteralPath (Join-Path $ProjectRoot 'firmware/robot_car/config.h') -Raw
$robotController = Get-Content -LiteralPath (Join-Path $ProjectRoot 'firmware/robot_car/controller.cpp') -Raw
$robotProtocol = Get-Content -LiteralPath (Join-Path $ProjectRoot 'firmware/robot_car/protocol.cpp') -Raw
$installAndroid = Get-Content -LiteralPath (Join-Path $ProjectRoot 'scripts/Install-Android.ps1') -Raw
Assert-Condition ($androidRootBuild.Contains("version `"$($androidLock.dependencies.android_gradle_plugin)`"")) 'Android Gradle plugin disagrees with android-toolchain.lock.json.'
Assert-Condition ($androidBuild.Contains("compileSdk = $($androidLock.sdk.compile)")) 'Android compile SDK disagrees with the lock.'
Assert-Condition ($androidBuild.Contains("targetSdk = $($androidLock.sdk.target)")) 'Android target SDK disagrees with the lock.'
Assert-Condition ($androidBuild.Contains("minSdk = $($androidLock.sdk.minimum)")) 'Android minimum SDK disagrees with the lock.'
foreach ($permission in @('BLUETOOTH_SCAN','BLUETOOTH_CONNECT','RECORD_AUDIO')) {
    Assert-Condition ($androidManifest.Contains("android.permission.$permission")) "Android manifest is missing $permission."
}
Assert-Condition ($androidManifest.Contains('android:localeConfig="@xml/locales_config"')) 'Android manifest must publish the supported app languages.'
Assert-Condition ($androidLocales.Contains('android:name="zh-CN"') -and $androidLocales.Contains('android:name="en"')) 'Android locale config must include Chinese and English.'
Assert-Condition ($androidLayout.Contains('@+id/language_zh') -and $androidLayout.Contains('@+id/language_en')) 'Android UI must expose both language choices.'
Assert-Condition ($androidLayout.Contains('@+id/line_mode_pulse') -and $androidLayout.Contains('@+id/line_mode_hybrid')) 'Android UI must expose Pulse and Normal line-drive profiles.'
Assert-Condition ($androidLayout.Contains('RaceJoystickView') -and $androidLayout.Contains('@+id/race_joystick') -and $androidLayout.Contains('@+id/speed_seek')) 'Android UI must expose the analog remote and its speed limit.'
Assert-Condition ($androidLayout.Contains('@+id/battery_value') -and $androidLayout.Contains('@+id/range_value') -and $androidLayout.Contains('@+id/line_center_indicator')) 'Android UI must expose the three live sensor groups.'
Assert-Condition (-not $androidLayout.Contains('<ScrollView')) 'Android controller must remain a one-page layout without scrolling.'
Assert-Condition ($androidLayout.Contains('@+id/horn_button')) 'Android controller must expose the hold-to-sound horn.'
Assert-Condition ($androidJoystick.Contains('onDriveStart') -and $androidJoystick.Contains('onDriveChanged') -and $androidJoystick.Contains('onDriveEnd')) 'Android analog remote must expose press, drag, and release states.'
Assert-Condition ($androidMixer.Contains('shapedThrottle + shapedSteering') -and $androidMixer.Contains('shapedThrottle - shapedSteering')) 'Android remote must retain differential throttle/steering mixing.'
Assert-Condition ($androidStringsEn.Contains('name="language_selector"') -and $androidStringsZh.Contains('name="language_selector"')) 'Both Android string sets must label the language selector.'
Assert-Condition ($androidStringsEn.Contains('name="line_mode_hybrid"') -and $androidStringsZh.Contains('name="line_mode_hybrid"')) 'Both Android string sets must label the line-drive selector.'
Assert-Condition ($androidActivity.Contains('setApplicationLocales') -and $androidActivity.Contains('UiLanguage.localeFor(currentUiLanguage())')) 'UI and speech language switching must stay wired together.'
Assert-Condition ($androidActivity.Contains('SpeechRecognizer.createSpeechRecognizer') -and $androidActivity.Contains('VoiceCommandParser.parseCandidates')) 'Android system speech recognition must remain connected to the bounded command parser.'
Assert-Condition ($voiceParser.Contains('Action { STOP, LINE, FORWARD, BACKWARD, LEFT, RIGHT, UNKNOWN }') -and $voiceParser.Contains('A stop hypothesis always wins')) 'Voice vocabulary or stop precedence changed outside the documented safety design.'
Assert-Condition ($androidBuild -match 'language\s*\{\s*enableSplit\s*=\s*false') 'Android bundle must keep both runtime-switchable languages installed.'
Assert-Condition ($bleClient -match 'LEGACY_CHUNK_BYTES\s*=\s*20') 'BLE UART chunks must remain compatible with the legacy 20-byte payload.'
Assert-Condition ($bleClient -match 'MAX_FRAME_BYTES\s*=\s*63') 'Android frame limit must match the firmware parser.'
Assert-Condition ($bleClient.Contains('removePendingRealtimeWrites') -and $bleClient.Contains('sendPriorityAscii')) 'BLE transport must coalesce joystick frames and let a safety command bypass stale work.'
Assert-Condition ($mobileController -match 'LINE_HEARTBEAT_MS\s*=\s*500') 'Line-mode heartbeat changed outside the documented lease design.'
Assert-Condition ($mobileController -match 'REMOTE_REFRESH_MS\s*=\s*50') 'Analog remote refresh must remain at the documented 20 Hz rate.'
Assert-Condition ($mobileController -match 'VOICE_PULSE_MS\s*=\s*1000') 'Voice movement must remain bounded to one second.'
Assert-Condition ($mobileProtocol -match 'DEFAULT_PWM\s*=\s*150') 'Android cold-start remote limit must match the accepted manual startup range.'
Assert-Condition ($mobileController.Contains('protocol.remoteDrive') -and -not $mobileController.Contains('protocol.speed(selectedPwm)')) 'Android analog remote must use the atomic wheel command instead of the old STOP/SPEED/ARM sequence.'
$startLineBlock = [regex]::Match($mobileController, '(?s)public void startLine\(\).*?public void beginRemote').Value
Assert-Condition (-not $startLineBlock.Contains('protocol.speed')) 'Android line start must not override the vehicle-side line pulse.'
Assert-Condition ($startLineBlock.Contains('protocol.stop()') -and $startLineBlock.Contains('lineModeFrame()') -and $startLineBlock.Contains('protocol.armLine()')) 'Android line start must stop, select a profile, then arm.'
Assert-Condition ($mobileProtocol.Contains('LINE PULSE') -and $mobileProtocol.Contains('LINE HYBRID')) 'Android protocol must encode Pulse and Normal line-drive profiles.'
Assert-Condition ($mobileProtocol.Contains('"R %d %d"') -and $mobileProtocol.Contains('"H 1"')) 'Android protocol must encode atomic remote drive and horn control.'
Assert-Condition ($robotProtocol.Contains('CommandType::LinePulse') -and $robotProtocol.Contains('CommandType::LineHybrid') -and $robotProtocol.Contains('CommandType::RemoteDrive') -and $robotProtocol.Contains('CommandType::HornOn')) 'Firmware parser must accept line profiles, atomic remote drive, and horn control.'
Assert-Condition ($robotController.Contains('LineDriveProfile::Hybrid ? -turn : 0') -and $robotController.Contains('return stopLinePulse(State::LineLost)')) 'Hybrid line drive must use the dedicated turn PWM on a single-side pattern and retain the lost-line interlock.'
Assert-Condition ($robotController.Contains('requested_.left) + requested_.right > 0')) 'Manual obstacle handling must block forward translation without dropping the remote session.'
Assert-Condition ($mobileProtocol -match 'FIRMWARE_MIN_PWM\s*=\s*50') 'Android protocol must retain the firmware calibration range.'
Assert-Condition ($mobileProtocol -match 'MIN_PWM\s*=\s*110') 'Android remote selector must not offer the measured non-starting range.'
Assert-Condition ($mobileProtocol -match 'MAX_PWM\s*=\s*200') 'Android wire PWM range must match firmware.'
Assert-Condition ($mobileProtocol -match 'REMOTE_MAX_PWM\s*=\s*180') 'Android selectable remote ceiling must match motor I/O clipping.'
Assert-Condition ($mobileController.Contains('pwm > RobotProtocol.REMOTE_MAX_PWM')) 'Android remote speed selection must enforce the 180 ceiling.'
Assert-Condition ($androidActivity.Contains('RobotProtocol.REMOTE_MAX_PWM - RobotProtocol.MIN_PWM')) 'Android speed slider must stop at the 180 ceiling.'
Assert-Condition ($mobileProtocol -match 'PWM_STEP\s*=\s*10') 'Android speed selector must use the documented step.'
Assert-Condition ($robotConfig -match 'cruise_pwm\s*=\s*100') 'Firmware default cruise PWM must match the slow startup profile.'
Assert-Condition ($robotConfig -match 'min_runtime_pwm\s*=\s*50') 'Firmware runtime speed minimum must match Android and host.'
Assert-Condition ($robotConfig -match 'line_pulse_pwm\s*=\s*120') 'Line following must use the measured startup PWM.'
Assert-Condition ($robotConfig -match 'line_turn_pwm\s*=\s*150') 'Normal line turns must use the verified bidirectional startup PWM.'
Assert-Condition ($robotConfig -match 'turn_reduction_pwm\s*=\s*120') 'Adjacent-line correction must stop the inner wheel for the current course.'
Assert-Condition ($robotConfig -match 'line_pulse_on_ms\s*=\s*80') 'Line drive pulse duration changed without updating the acceptance plan.'
Assert-Condition ($robotConfig -match 'line_pulse_off_ms\s*=\s*80') 'Line coast pulse duration changed without updating the acceptance plan.'
Assert-Condition ($robotConfig -match 'max_pwm\s*=\s*200') 'Firmware wire PWM range must match Android.'
Assert-Condition ($robotConfig -match 'horn_lease_ms\s*=\s*1500') 'Manual horn must retain its disconnect timeout.'
Assert-Condition ($hostProtocol.Contains('-200 <= value <= 200')) 'Host protocol PWM must match the firmware ceiling.'
Assert-Condition ($hostProtocol.Contains('not 50 <= speed <= 200')) 'Host speed bounds must match the firmware calibration range.'
Assert-Condition ($robotScript.Contains('ValidateRange(-200,200)')) 'PowerShell control bounds must match the firmware ceiling.'
Assert-Condition ($installAndroid.Contains('if (-not $ConfirmDeviceReady)')) 'Phone installation must require explicit device confirmation.'
$trackedApks = @(& git -C $ProjectRoot ls-files '*.apk')
Assert-Condition ($LASTEXITCODE -eq 0 -and $trackedApks.Count -eq 0) 'APK binaries must not be tracked in Git.'
Write-Host 'PASS: Android versions, bilingual UI, permissions, bounded controls, BLE framing, and install gate.'

$usb = Get-Content -LiteralPath (Join-Path $ProjectRoot 'firmware/usb_check/usb_check.ino') -Raw
Assert-Condition (-not ($usb -match 'analogWrite|Servo\.h|motorRun|servo\.attach')) 'USB-only check must not control actuators.'
Assert-Condition ($usb.Contains('Serial.begin(115200)')) 'USB check baud rate changed; update the bring-up contract.'
Write-Host 'PASS: USB-only source guard (static check, not a hardware test).'

$servoCheck = Get-Content -LiteralPath (Join-Path $ProjectRoot 'firmware/servo_check/servo_check.ino') -Raw
$trimMatch = [regex]::Match($servoCheck, 'kServoTrimDegrees\s*=\s*([+-]?\d+)')
$sweepMatch = [regex]::Match($servoCheck, 'kSweepDegrees\s*=\s*(\d+)')
Assert-Condition $trimMatch.Success 'Servo diagnostic must declare a numeric trim.'
Assert-Condition $sweepMatch.Success 'Servo diagnostic must declare a numeric sweep.'
$servoTrim = [int]$trimMatch.Groups[1].Value
$servoSweep = [int]$sweepMatch.Groups[1].Value
Assert-Condition ([Math]::Abs($servoTrim) -le 10) 'Servo trim exceeds the vendor calibration range.'
Assert-Condition ($servoSweep -gt 0 -and $servoSweep -le 10) 'Servo diagnostic sweep must stay within 1..10 degrees.'
$centerMatch = [regex]::Match($robotConfig, 'servo_center_degrees\s*=\s*(\d+)')
Assert-Condition $centerMatch.Success 'Robot controller must declare a numeric servo center.'
$robotCenter = [int]$centerMatch.Groups[1].Value
Assert-Condition ($robotCenter -eq (90 + $servoTrim)) 'Servo diagnostic trim and robot controller center disagree.'
Write-Host "PASS: Servo diagnostic trim $servoTrim degrees and sweep +/-$servoSweep degrees are bounded."

$motorCheck = Get-Content -LiteralPath (Join-Path $ProjectRoot 'firmware/motor_check/motor_check.ino') -Raw
$drivePwmMatch = [regex]::Match($motorCheck, 'kDrivePwm\s*=\s*(\d+)')
$runMsMatch = [regex]::Match($motorCheck, 'kRunMs\s*=\s*(\d+)')
Assert-Condition $drivePwmMatch.Success 'Motor diagnostic must declare a numeric PWM limit.'
Assert-Condition $runMsMatch.Success 'Motor diagnostic must declare a numeric run-time limit.'
$drivePwm = [int]$drivePwmMatch.Groups[1].Value
$runMs = [int]$runMsMatch.Groups[1].Value
Assert-Condition ($drivePwm -gt 0 -and $drivePwm -le 200) 'Motor diagnostic PWM must stay within 1..200.'
Assert-Condition ($runMs -gt 0 -and $runMs -le 1000) 'Motor diagnostic run time must stay within 1..1000 ms.'
Assert-Condition (-not ($motorCheck -match 'pulseIn|analogRead|Servo\.h|servo\.attach')) 'Motor diagnostic must remain independent of sensors and the servo.'
Assert-Condition ($motorCheck.Contains('void loop()') -and $motorCheck.Contains('stopMotors();')) 'Motor diagnostic must retain its stopped loop.'
Assert-Condition ($robotConfig -match 'invert_left_motor\s*=\s*true') 'Physical calibration requires the left motor polarity inversion.'
Assert-Condition ($robotConfig -match 'invert_right_motor\s*=\s*true') 'Physical calibration requires the right motor polarity inversion.'
Assert-Condition ($robotConfig -match 'black_reads_high\s*=\s*true') 'Freenove tracking sensors report black or no reflection as HIGH.'
Assert-Condition ($motorCheck.Contains('digitalWrite(kDirectionLeft, HIGH);')) 'Motor diagnostic left polarity disagrees with the calibrated controller.'
Assert-Condition ($motorCheck.Contains('digitalWrite(kDirectionRight, LOW);')) 'Motor diagnostic right polarity disagrees with the calibrated controller.'
Write-Host "PASS: Motor diagnostic is sensor-independent and bounded to PWM $drivePwm for $runMs ms."

$rejected = $false
try {
    & (Join-Path $ProjectRoot 'scripts/Upload.ps1') -Program usb_check -Port 'NOT-A-REAL-PORT'
} catch {
    $rejected = $_.Exception.Message -like 'Upload requires -ConfirmHardwareReady*'
}
Assert-Condition $rejected 'Upload must reject missing physical confirmation before accessing hardware.'
Write-Host 'PASS: Upload refused without hardware confirmation; no port accessed.'
foreach ($case in @(@{Action='observe';Port='COM9999'}, @{Action='line';Port='COM9999';ConfirmHardwareReady=$true})) {
    $rejected = $false
    try { & (Join-Path $ProjectRoot 'scripts/Robot.ps1') @case }
    catch { $rejected = $_.Exception.Message -match 'requires -ConfirmHardwareReady|requires -ConfirmMotionClear' }
    Assert-Condition $rejected 'Robot operation did not enforce setup/motion confirmation.'
}
Write-Host 'PASS: Robot sessions refuse missing setup/motion confirmation; no port accessed.'
Write-Host 'All repository checks passed. No hardware was tested.'
