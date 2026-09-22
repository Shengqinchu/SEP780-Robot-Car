package io.github.shengqinchu.sep780;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.AlertDialog;
import android.app.LocaleManager;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothManager;
import android.bluetooth.le.BluetoothLeScanner;
import android.bluetooth.le.ScanCallback;
import android.bluetooth.le.ScanRecord;
import android.bluetooth.le.ScanResult;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.res.Configuration;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.LocaleList;
import android.speech.RecognitionListener;
import android.speech.RecognizerIntent;
import android.speech.SpeechRecognizer;
import android.view.MotionEvent;
import android.view.View;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.RadioGroup;
import android.widget.SeekBar;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;

public final class MainActivity extends Activity implements BleUartClient.Listener,
        RobotCommandController.Listener {
    private static final int REQUEST_BLUETOOTH_PERMISSIONS = 100;
    private static final int REQUEST_AUDIO_PERMISSION = 101;
    private static final int REQUEST_ENABLE_BLUETOOTH = 102;
    private static final long SCAN_DURATION_MS = 8000;
    private static final String PREFS = "robot_car";
    private static final String LAST_DEVICE = "last_device";
    private static final String UI_LANGUAGE = "ui_language";

    private final Handler main = new Handler(Looper.getMainLooper());
    private final List<ScanEntry> scanEntries = new ArrayList<>();
    private BluetoothAdapter bluetoothAdapter;
    private BluetoothLeScanner scanner;
    private BleUartClient ble;
    private RobotCommandController controller;
    private SpeechRecognizer speechRecognizer;
    private boolean speechAvailable;
    private boolean scanning;
    private boolean pendingScan;
    private boolean pendingReconnect;
    private boolean pendingVoice;
    private ArrayAdapter<String> scanAdapter;
    private AlertDialog scanDialog;

    private TextView connectionState;
    private TextView connectionIndicator;
    private TextView transcriptText;
    private TextView commandState;
    private TextView batteryValue;
    private TextView rangeValue;
    private TextView lineValue;
    private TextView telemetryText;
    private TextView lastMessage;
    private View lineLeftIndicator;
    private View lineCenterIndicator;
    private View lineRightIndicator;
    private RaceJoystickView joystickView;
    private SeekBar speedSeek;
    private TextView speedLimitValue;
    private Button scanButton;
    private Button reconnectButton;
    private Button disconnectButton;
    private Button voiceButton;
    private Button hornButton;
    private Button lineButton;
    private Button stopButton;
    private RadioGroup languageGroup;
    private RadioGroup lineModeGroup;

    private static final class ScanEntry {
        private BluetoothDevice device;
        private final String address;
        private String name;
        private int rssi;

        private ScanEntry(BluetoothDevice device, String address, String name, int rssi) {
            this.device = device;
            this.address = address;
            this.name = name;
            this.rssi = rssi;
        }

        private String label() {
            return name + "\n" + address + "  " + rssi + " dBm";
        }
    }

    @Override
    protected void attachBaseContext(Context newBase) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            super.attachBaseContext(newBase);
            return;
        }
        String saved = newBase.getSharedPreferences(PREFS, MODE_PRIVATE)
                .getString(UI_LANGUAGE, null);
        String language = UiLanguage.resolve(saved, Locale.getDefault());
        Locale locale = UiLanguage.localeFor(language);
        Locale.setDefault(locale);
        Configuration configuration = new Configuration(newBase.getResources().getConfiguration());
        configuration.setLocale(locale);
        configuration.setLayoutDirection(locale);
        super.attachBaseContext(newBase.createConfigurationContext(configuration));
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        bindViews();

        BluetoothManager manager = (BluetoothManager) getSystemService(BLUETOOTH_SERVICE);
        bluetoothAdapter = manager == null ? null : manager.getAdapter();
        ble = new BleUartClient(this, this);
        controller = new RobotCommandController(new RobotCommandController.Transport() {
            @Override public boolean isReady() { return ble.isReady(); }
            @Override public boolean sendAscii(String frame) { return ble.sendAscii(frame); }
            @Override public boolean sendRealtimeAscii(String frame) { return ble.sendRealtimeAscii(frame); }
            @Override public boolean sendPriorityAscii(String frame) { return ble.sendPriorityAscii(frame); }
        }, this);

        initializeSpeech();
        bindActions();
        updateControls(BleUartClient.State.DISCONNECTED);
    }

    private void bindViews() {
        connectionState = findViewById(R.id.connection_state);
        connectionIndicator = findViewById(R.id.connection_indicator);
        transcriptText = findViewById(R.id.transcript_text);
        commandState = findViewById(R.id.command_state);
        batteryValue = findViewById(R.id.battery_value);
        rangeValue = findViewById(R.id.range_value);
        lineValue = findViewById(R.id.line_value);
        telemetryText = findViewById(R.id.telemetry_text);
        lastMessage = findViewById(R.id.last_message);
        lineLeftIndicator = findViewById(R.id.line_left_indicator);
        lineCenterIndicator = findViewById(R.id.line_center_indicator);
        lineRightIndicator = findViewById(R.id.line_right_indicator);
        joystickView = findViewById(R.id.race_joystick);
        speedSeek = findViewById(R.id.speed_seek);
        speedLimitValue = findViewById(R.id.speed_limit_value);
        scanButton = findViewById(R.id.scan_button);
        reconnectButton = findViewById(R.id.reconnect_button);
        disconnectButton = findViewById(R.id.disconnect_button);
        voiceButton = findViewById(R.id.voice_button);
        hornButton = findViewById(R.id.horn_button);
        lineButton = findViewById(R.id.line_button);
        stopButton = findViewById(R.id.stop_button);
        languageGroup = findViewById(R.id.language_group);
        lineModeGroup = findViewById(R.id.line_mode_group);
    }

    private void bindActions() {
        bindLanguageSelector();
        bindLineModeSelector();
        scanButton.setOnClickListener(view -> requestScan());
        reconnectButton.setOnClickListener(view -> reconnectLastDevice());
        disconnectButton.setOnClickListener(view -> {
            controller.stop();
            main.postDelayed(ble::disconnect, 300);
        });
        voiceButton.setOnClickListener(view -> requestVoice());
        bindHornButton();
        lineButton.setOnClickListener(view -> controller.startLine());
        stopButton.setOnClickListener(view -> controller.stop());
        int speedSteps = (RobotProtocol.MAX_PWM - RobotProtocol.MIN_PWM) / RobotProtocol.PWM_STEP;
        speedSeek.setMax(speedSteps);
        speedSeek.setProgress((controller.selectedPwm() - RobotProtocol.MIN_PWM) / RobotProtocol.PWM_STEP);
        updateSpeedLabel(controller.selectedPwm());
        speedSeek.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override public void onStartTrackingTouch(SeekBar seekBar) {
                controller.stop();
            }

            @Override public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                updateSpeedLabel(RobotProtocol.MIN_PWM + progress * RobotProtocol.PWM_STEP);
            }

            @Override public void onStopTrackingTouch(SeekBar seekBar) {
                controller.selectSpeed(RobotProtocol.MIN_PWM +
                        seekBar.getProgress() * RobotProtocol.PWM_STEP);
            }
        });
        joystickView.setListener(new RaceJoystickView.Listener() {
            @Override public void onDriveStart(float throttle, float steering) {
                controller.beginRemote(throttle, steering);
            }

            @Override public void onDriveChanged(float throttle, float steering) {
                controller.updateRemote(throttle, steering);
            }

            @Override public void onDriveEnd() {
                controller.endRemote();
            }
        });
    }

    private void bindLanguageSelector() {
        String language = currentUiLanguage();
        languageGroup.check(UiLanguage.SIMPLIFIED_CHINESE.equals(language)
                ? R.id.language_zh : R.id.language_en);
        languageGroup.setOnCheckedChangeListener((group, checkedId) -> {
            String selected = checkedId == R.id.language_zh
                    ? UiLanguage.SIMPLIFIED_CHINESE : UiLanguage.ENGLISH;
            changeUiLanguage(selected);
        });
    }

    private void bindLineModeSelector() {
        lineModeGroup.check(controller.selectedLineMode() == RobotCommandController.LineMode.PULSE
                ? R.id.line_mode_pulse : R.id.line_mode_hybrid);
        lineModeGroup.setOnCheckedChangeListener((group, checkedId) ->
                controller.selectLineMode(checkedId == R.id.line_mode_hybrid
                        ? RobotCommandController.LineMode.HYBRID
                        : RobotCommandController.LineMode.PULSE));
    }

    private String currentUiLanguage() {
        Locale fallback = getResources().getConfiguration().getLocales().get(0);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            LocaleManager manager = getSystemService(LocaleManager.class);
            if (manager != null) {
                LocaleList locales = manager.getApplicationLocales();
                if (!locales.isEmpty()) return UiLanguage.resolve(locales.get(0).toLanguageTag(), fallback);
            }
        }
        String saved = getSharedPreferences(PREFS, MODE_PRIVATE).getString(UI_LANGUAGE, null);
        return UiLanguage.resolve(saved, fallback);
    }

    private void changeUiLanguage(String language) {
        if (currentUiLanguage().equals(language)) return;
        Runnable apply = () -> applyUiLanguage(language);
        if (ble != null && ble.isReady()) {
            controller.stop();
            main.postDelayed(() -> {
                ble.disconnect();
                apply.run();
            }, 300);
            return;
        }
        apply.run();
    }

    private void applyUiLanguage(String language) {
        getSharedPreferences(PREFS, MODE_PRIVATE).edit().putString(UI_LANGUAGE, language).apply();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            LocaleManager manager = getSystemService(LocaleManager.class);
            if (manager != null) {
                manager.setApplicationLocales(LocaleList.forLanguageTags(language));
                return;
            }
        }
        recreate();
    }

    private void updateSpeedLabel(int pwm) {
        speedLimitValue.setText(getString(R.string.speed_limit_value, pwm));
        joystickView.setMaxPwm(pwm);
    }

    @SuppressLint("ClickableViewAccessibility")
    private void bindHornButton() {
        hornButton.setOnClickListener(view -> { });
        hornButton.setOnTouchListener((view, event) -> {
            int action = event.getActionMasked();
            if (action == MotionEvent.ACTION_DOWN) {
                controller.beginHorn();
                return true;
            }
            if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) {
                controller.endHorn();
                view.performClick();
                return true;
            }
            return false;
        });
    }

    private void initializeSpeech() {
        speechAvailable = SpeechRecognizer.isRecognitionAvailable(this);
        if (!speechAvailable) {
            transcriptText.setText(R.string.voice_unavailable);
            return;
        }
        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this);
        speechRecognizer.setRecognitionListener(recognitionListener);
    }

    private void requestVoice() {
        if (!speechAvailable || speechRecognizer == null) {
            transcriptText.setText(R.string.voice_unavailable);
            return;
        }
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            pendingVoice = true;
            requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO}, REQUEST_AUDIO_PERMISSION);
            return;
        }
        startVoiceRecognition();
    }

    private void startVoiceRecognition() {
        Intent intent = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
        intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
        intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE,
                UiLanguage.localeFor(currentUiLanguage()).toLanguageTag());
        intent.putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5);
        intent.putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true);
        transcriptText.setText(R.string.voice_listening);
        speechRecognizer.startListening(intent);
    }

    private final RecognitionListener recognitionListener = new RecognitionListener() {
        @Override public void onReadyForSpeech(Bundle params) { transcriptText.setText(R.string.voice_listening); }
        @Override public void onBeginningOfSpeech() { }
        @Override public void onRmsChanged(float rmsdB) { }
        @Override public void onBufferReceived(byte[] buffer) { }
        @Override public void onEndOfSpeech() { transcriptText.setText(R.string.voice_processing); }
        @Override public void onEvent(int eventType, Bundle params) { }

        @Override
        public void onError(int error) {
            transcriptText.setText(getString(R.string.voice_error, error));
        }

        @Override
        public void onResults(Bundle results) {
            ArrayList<String> phrases = results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
            showRecognizedPhrase(phrases);
            executeVoiceAction(VoiceCommandParser.parseCandidates(phrases));
        }

        @Override
        public void onPartialResults(Bundle partialResults) {
            ArrayList<String> phrases = partialResults.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
            showRecognizedPhrase(phrases);
        }
    };

    private void showRecognizedPhrase(List<String> phrases) {
        if (phrases != null && !phrases.isEmpty()) {
            transcriptText.setText(getString(R.string.recognized_phrase, phrases.get(0)));
        }
    }

    private void executeVoiceAction(VoiceCommandParser.Action action) {
        switch (action) {
            case STOP:
                controller.stop();
                break;
            case LINE:
                controller.startLine();
                break;
            case FORWARD:
                controller.voicePulse(RobotCommandController.Direction.FORWARD);
                break;
            case BACKWARD:
                controller.voicePulse(RobotCommandController.Direction.BACKWARD);
                break;
            case LEFT:
                controller.voicePulse(RobotCommandController.Direction.LEFT);
                break;
            case RIGHT:
                controller.voicePulse(RobotCommandController.Direction.RIGHT);
                break;
            default:
                commandState.setText(R.string.voice_unknown);
        }
    }

    @SuppressLint("MissingPermission")
    private void requestScan() {
        if (bluetoothAdapter == null) {
            connectionState.setText(R.string.bluetooth_unavailable);
            return;
        }
        if (!hasBluetoothPermissions()) {
            pendingScan = true;
            pendingReconnect = false;
            requestPermissions(bluetoothPermissions(), REQUEST_BLUETOOTH_PERMISSIONS);
            return;
        }
        if (!bluetoothAdapter.isEnabled()) {
            pendingScan = true;
            pendingReconnect = false;
            startActivityForResult(new Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE), REQUEST_ENABLE_BLUETOOTH);
            return;
        }
        startScan();
    }

    @SuppressLint("MissingPermission")
    private void startScan() {
        scanner = bluetoothAdapter.getBluetoothLeScanner();
        if (scanner == null) {
            connectionState.setText(R.string.enable_bluetooth);
            return;
        }
        stopScan(false);
        scanEntries.clear();
        scanAdapter = new ArrayAdapter<>(this, android.R.layout.simple_list_item_1, new ArrayList<>());
        scanDialog = new AlertDialog.Builder(this)
                .setTitle(R.string.scanning)
                .setAdapter(scanAdapter, (dialog, which) -> connectTo(scanEntries.get(which).device))
                .setNegativeButton(R.string.cancel, (dialog, which) -> stopScan(false))
                .create();
        scanDialog.setOnDismissListener(dialog -> stopScan(false));
        scanDialog.show();
        scanning = true;
        updateControls(BleUartClient.State.DISCONNECTED);
        scanner.startScan(scanCallback);
        main.postDelayed(() -> stopScan(true), SCAN_DURATION_MS);
    }

    @SuppressLint("MissingPermission")
    private void stopScan(boolean completed) {
        if (scanning && scanner != null) {
            try { scanner.stopScan(scanCallback); } catch (SecurityException ignored) { }
        }
        scanning = false;
        if (completed && scanDialog != null && scanDialog.isShowing()) {
            scanDialog.setTitle(R.string.scan_finished);
        }
        updateControls(ble != null && ble.isReady() ? BleUartClient.State.READY : BleUartClient.State.DISCONNECTED);
    }

    private final ScanCallback scanCallback = new ScanCallback() {
        @Override
        public void onScanResult(int callbackType, ScanResult result) {
            main.post(() -> addScanResult(result));
        }

        @Override
        public void onScanFailed(int errorCode) {
            main.post(() -> {
                stopScan(false);
                connectionState.setText(getString(R.string.scan_error, errorCode));
            });
        }
    };

    @SuppressLint("MissingPermission")
    private void addScanResult(ScanResult result) {
        BluetoothDevice device = result.getDevice();
        String address;
        try { address = device.getAddress(); } catch (SecurityException exception) { return; }
        String name = null;
        ScanRecord record = result.getScanRecord();
        if (record != null) name = record.getDeviceName();
        if (name == null || name.trim().isEmpty()) {
            try { name = device.getName(); } catch (SecurityException exception) { name = null; }
        }
        if (name == null || name.trim().isEmpty()) name = getString(R.string.unnamed_device);

        ScanEntry existing = null;
        for (ScanEntry entry : scanEntries) {
            if (entry.address.equals(address)) {
                existing = entry;
                break;
            }
        }
        if (existing == null) {
            scanEntries.add(new ScanEntry(device, address, name, result.getRssi()));
        } else {
            existing.device = device;
            existing.name = name;
            existing.rssi = result.getRssi();
        }

        scanEntries.sort(Comparator.comparingInt((ScanEntry entry) -> entry.rssi).reversed());
        scanAdapter.clear();
        for (ScanEntry entry : scanEntries) scanAdapter.add(entry.label());
        scanAdapter.notifyDataSetChanged();
    }

    @SuppressLint("MissingPermission")
    private void connectTo(BluetoothDevice device) {
        stopScan(false);
        if (scanDialog != null) scanDialog.dismiss();
        try {
            getSharedPreferences(PREFS, MODE_PRIVATE).edit().putString(LAST_DEVICE, device.getAddress()).apply();
        } catch (SecurityException ignored) { }
        ble.connect(device);
    }

    @SuppressLint("MissingPermission")
    private void reconnectLastDevice() {
        if (!hasBluetoothPermissions()) {
            pendingReconnect = true;
            pendingScan = false;
            requestPermissions(bluetoothPermissions(), REQUEST_BLUETOOTH_PERMISSIONS);
            return;
        }
        String address = getSharedPreferences(PREFS, MODE_PRIVATE).getString(LAST_DEVICE, null);
        if (address == null || bluetoothAdapter == null) return;
        try {
            if (!bluetoothAdapter.isEnabled()) {
                pendingReconnect = true;
                pendingScan = false;
                startActivityForResult(new Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE), REQUEST_ENABLE_BLUETOOTH);
                return;
            }
            ble.connect(bluetoothAdapter.getRemoteDevice(address));
        } catch (IllegalArgumentException | SecurityException exception) {
            connectionState.setText(R.string.connection_error);
        }
    }

    private boolean hasBluetoothPermissions() {
        for (String permission : bluetoothPermissions()) {
            if (checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) return false;
        }
        return true;
    }

    private static String[] bluetoothPermissions() {
        if (Build.VERSION.SDK_INT >= 31) {
            return new String[]{Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT};
        }
        return new String[]{Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION};
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        boolean granted = grantResults.length > 0;
        for (int result : grantResults) granted &= result == PackageManager.PERMISSION_GRANTED;
        if (requestCode == REQUEST_BLUETOOTH_PERMISSIONS) {
            boolean scan = pendingScan;
            boolean reconnect = pendingReconnect;
            pendingScan = false;
            pendingReconnect = false;
            if (granted && reconnect) reconnectLastDevice();
            else if (granted && scan) requestScan();
            else connectionState.setText(R.string.bluetooth_permission_denied);
        } else if (requestCode == REQUEST_AUDIO_PERMISSION) {
            if (granted && pendingVoice) startVoiceRecognition();
            else transcriptText.setText(R.string.audio_permission_denied);
            pendingVoice = false;
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQUEST_ENABLE_BLUETOOTH) {
            boolean scan = pendingScan;
            boolean reconnect = pendingReconnect;
            pendingScan = false;
            pendingReconnect = false;
            if (resultCode == RESULT_OK && reconnect) reconnectLastDevice();
            else if (resultCode == RESULT_OK && scan) requestScan();
            else connectionState.setText(R.string.enable_bluetooth);
        }
    }

    @Override
    public void onBleState(BleUartClient.State state, String detail) {
        switch (state) {
            case CONNECTING:
                connectionState.setText(R.string.connecting);
                break;
            case DISCOVERING:
                connectionState.setText(R.string.discovering);
                break;
            case READY:
                connectionState.setText(R.string.connected);
                controller.requestStatus();
                break;
            case ERROR:
                connectionState.setText(getString(R.string.connection_error_detail, detail));
                controller.transportDisconnected();
                break;
            default:
                connectionState.setText(R.string.disconnected);
                controller.transportDisconnected();
        }
        updateControls(state);
    }

    @Override
    public void onBleLine(String line) {
        lastMessage.setText(getString(R.string.last_reply, line));
        TelemetryParser.Telemetry telemetry = TelemetryParser.parse(line);
        if (telemetry != null) {
            telemetryText.setText(getString(R.string.telemetry_format,
                    telemetry.mode, telemetry.state, telemetry.lineBits, telemetry.rangeMm,
                    telemetry.batteryMv / 1000.0, telemetry.leftPwm, telemetry.rightPwm));
            joystickView.setTelemetry(telemetry.leftPwm, telemetry.rightPwm);
            batteryValue.setText(getString(R.string.battery_value, telemetry.batteryMv / 1000.0));
            rangeValue.setText(getString(R.string.range_value, telemetry.rangeMm));
            String bits = String.format(Locale.ROOT, "%3s",
                    Integer.toBinaryString(telemetry.lineBits)).replace(' ', '0');
            lineValue.setText(getString(R.string.line_value, bits));
            updateLineIndicators(telemetry.lineBits);
        }
        if (line.startsWith("ERR ")) controller.commandRejected();
    }

    private void updateLineIndicators(int bits) {
        lineLeftIndicator.setBackgroundResource((bits & 4) != 0
                ? R.drawable.sensor_active : R.drawable.sensor_inactive);
        lineCenterIndicator.setBackgroundResource((bits & 2) != 0
                ? R.drawable.sensor_active : R.drawable.sensor_inactive);
        lineRightIndicator.setBackgroundResource((bits & 1) != 0
                ? R.drawable.sensor_active : R.drawable.sensor_inactive);
    }

    @Override
    public void onControlState(String state) {
        int resource;
        switch (state) {
            case "line_pending": resource = R.string.control_line_pending; break;
            case "line": resource = R.string.control_line; break;
            case "manual_pending": resource = R.string.control_manual_pending; break;
            case "manual": resource = R.string.control_manual; break;
            case "speed_selected": resource = R.string.control_speed_selected; break;
            case "line_mode_selected": resource = R.string.control_line_mode_selected; break;
            case "not_connected": resource = R.string.control_not_connected; break;
            case "command_error": resource = R.string.control_command_error; break;
            case "disconnected": resource = R.string.disconnected; break;
            default: resource = R.string.control_stopped;
        }
        commandState.setText(resource);
    }

    @Override
    public void onFrameSent(String frame) {
        lastMessage.setText(getString(R.string.last_command, frame));
    }

    private void updateControls(BleUartClient.State state) {
        boolean ready = state == BleUartClient.State.READY && ble != null && ble.isReady();
        boolean busy = state == BleUartClient.State.CONNECTING || state == BleUartClient.State.DISCOVERING;
        int indicatorColor;
        if (ready) indicatorColor = R.color.bluetooth_blue;
        else if (busy) indicatorColor = R.color.warning;
        else if (state == BleUartClient.State.ERROR) indicatorColor = R.color.danger;
        else indicatorColor = R.color.inactive;
        connectionIndicator.setTextColor(getColor(indicatorColor));
        joystickView.setEnabled(ready);
        speedSeek.setEnabled(ready);
        scanButton.setEnabled(!scanning && !busy);
        String last = getSharedPreferences(PREFS, MODE_PRIVATE).getString(LAST_DEVICE, null);
        reconnectButton.setEnabled(last != null && !ready && !busy && !scanning);
        disconnectButton.setEnabled(ready || busy);
        voiceButton.setEnabled(ready && speechAvailable);
        hornButton.setEnabled(ready);
        lineButton.setEnabled(ready);
        stopButton.setEnabled(ready);
    }

    @Override
    protected void onPause() {
        super.onPause();
        if (controller != null) controller.stop();
        if (speechRecognizer != null) speechRecognizer.cancel();
    }

    @Override
    protected void onDestroy() {
        stopScan(false);
        if (controller != null) controller.shutdown();
        if (speechRecognizer != null) speechRecognizer.destroy();
        if (ble != null) ble.close();
        super.onDestroy();
    }
}
