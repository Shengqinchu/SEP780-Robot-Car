package io.github.shengqinchu.sep780;

import android.annotation.SuppressLint;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCallback;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothGattDescriptor;
import android.bluetooth.BluetoothGattService;
import android.bluetooth.BluetoothProfile;
import android.bluetooth.BluetoothStatusCodes;
import android.content.Context;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;

import java.nio.charset.StandardCharsets;
import java.util.ArrayDeque;
import java.util.Locale;
import java.util.UUID;

/** Small BLE UART client for BT05/JDY-style transparent serial modules. */
public final class BleUartClient {
    public enum State { DISCONNECTED, CONNECTING, DISCOVERING, READY, ERROR }

    public interface Listener {
        void onBleState(State state, String detail);
        void onBleLine(String line);
    }

    private static final UUID CCCD = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");
    private static final int LEGACY_CHUNK_BYTES = 20;
    private static final int MAX_FRAME_BYTES = 63;
    private static final long NO_RESPONSE_PACING_MS = 30;

    private final Context context;
    private final Listener listener;
    private final Handler main = new Handler(Looper.getMainLooper());
    private static final class PendingWrite {
        private final byte[] value;
        private final boolean realtime;

        private PendingWrite(byte[] value, boolean realtime) {
            this.value = value;
            this.realtime = realtime;
        }
    }

    private final ArrayDeque<PendingWrite> writeQueue = new ArrayDeque<>();
    private final StringBuilder incoming = new StringBuilder();
    private BluetoothGatt gatt;
    private BluetoothGattCharacteristic writeCharacteristic;
    private boolean ready;
    private boolean writeWithResponse;
    private boolean writeInFlight;

    public BleUartClient(Context context, Listener listener) {
        this.context = context.getApplicationContext();
        this.listener = listener;
    }

    public boolean isReady() {
        return ready;
    }

    @SuppressLint("MissingPermission")
    public void connect(BluetoothDevice device) {
        closeInternal();
        listener.onBleState(State.CONNECTING, safeName(device));
        try {
            gatt = device.connectGatt(context, false, callback, BluetoothDevice.TRANSPORT_LE);
            if (gatt == null) fail("GATT connection could not be created.");
        } catch (SecurityException | IllegalArgumentException exception) {
            fail("Bluetooth connection failed: " + exception.getClass().getSimpleName());
        }
    }

    @SuppressLint("MissingPermission")
    public void disconnect() {
        ready = false;
        writeQueue.clear();
        writeInFlight = false;
        BluetoothGatt active = gatt;
        if (active == null) {
            listener.onBleState(State.DISCONNECTED, "");
            return;
        }
        try {
            active.disconnect();
        } catch (SecurityException exception) {
            closeInternal();
            listener.onBleState(State.DISCONNECTED, "");
            return;
        }
        main.postDelayed(() -> {
            if (gatt == active) {
                closeInternal();
                listener.onBleState(State.DISCONNECTED, "");
            }
        }, 1000);
    }

    public void close() {
        closeInternal();
    }

    public boolean sendAscii(String frame) {
        return enqueueFrame(frame, false, false);
    }

    /** Replaces queued joystick samples while preserving the GATT write in flight. */
    public boolean sendRealtimeAscii(String frame) {
        return enqueueFrame(frame, true, false);
    }

    /** Drops stale pending work so STOP or the first takeover frame goes next. */
    public boolean sendPriorityAscii(String frame) {
        return enqueueFrame(frame, false, true);
    }

    private boolean enqueueFrame(String frame, boolean realtime, boolean priority) {
        if (!ready || gatt == null || writeCharacteristic == null || frame == null) return false;
        byte[] bytes = frame.getBytes(StandardCharsets.US_ASCII);
        if (bytes.length == 0 || bytes.length > MAX_FRAME_BYTES || bytes[bytes.length - 1] != '\n') return false;
        for (int i = 0; i < frame.length(); ++i) {
            if (frame.charAt(i) > 0x7f) return false;
        }
        if (priority) clearPendingWrites();
        else if (realtime) removePendingRealtimeWrites();
        for (int offset = 0; offset < bytes.length; offset += LEGACY_CHUNK_BYTES) {
            int count = Math.min(LEGACY_CHUNK_BYTES, bytes.length - offset);
            byte[] chunk = new byte[count];
            System.arraycopy(bytes, offset, chunk, 0, count);
            writeQueue.addLast(new PendingWrite(chunk, realtime));
        }
        pumpWrites();
        return true;
    }

    private void clearPendingWrites() {
        PendingWrite active = writeInFlight ? writeQueue.pollFirst() : null;
        writeQueue.clear();
        if (active != null) writeQueue.addFirst(active);
    }

    private void removePendingRealtimeWrites() {
        PendingWrite active = writeInFlight ? writeQueue.pollFirst() : null;
        writeQueue.removeIf(pending -> pending.realtime);
        if (active != null) writeQueue.addFirst(active);
    }

    private final BluetoothGattCallback callback = new BluetoothGattCallback() {
        @Override
        public void onConnectionStateChange(BluetoothGatt callbackGatt, int status, int newState) {
            main.post(() -> handleConnectionState(callbackGatt, status, newState));
        }

        @Override
        public void onServicesDiscovered(BluetoothGatt callbackGatt, int status) {
            main.post(() -> handleServices(callbackGatt, status));
        }

        @Override
        public void onDescriptorWrite(BluetoothGatt callbackGatt, BluetoothGattDescriptor descriptor, int status) {
            main.post(() -> {
                if (callbackGatt != gatt) return;
                markReady(status == BluetoothGatt.GATT_SUCCESS ? "notifications enabled" : "write only");
            });
        }

        @Override
        public void onCharacteristicWrite(BluetoothGatt callbackGatt,
                                          BluetoothGattCharacteristic characteristic, int status) {
            main.post(() -> handleWrite(callbackGatt, status));
        }

        @Override
        public void onCharacteristicChanged(BluetoothGatt callbackGatt,
                                            BluetoothGattCharacteristic characteristic, byte[] value) {
            byte[] copy = value == null ? new byte[0] : value.clone();
            main.post(() -> consumeIncoming(copy));
        }

        @SuppressWarnings("deprecation")
        @Override
        public void onCharacteristicChanged(BluetoothGatt callbackGatt,
                                            BluetoothGattCharacteristic characteristic) {
            byte[] value = characteristic.getValue();
            byte[] copy = value == null ? new byte[0] : value.clone();
            main.post(() -> consumeIncoming(copy));
        }
    };

    @SuppressLint("MissingPermission")
    private void handleConnectionState(BluetoothGatt callbackGatt, int status, int newState) {
        if (callbackGatt != gatt) return;
        if (status != BluetoothGatt.GATT_SUCCESS) {
            fail("GATT status " + status);
            return;
        }
        if (newState == BluetoothProfile.STATE_CONNECTED) {
            ready = false;
            listener.onBleState(State.DISCOVERING, "services");
            try {
                callbackGatt.requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_HIGH);
                if (!callbackGatt.discoverServices()) fail("Service discovery did not start.");
            } catch (SecurityException exception) {
                fail("Bluetooth permission was lost.");
            }
        } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
            closeInternal();
            listener.onBleState(State.DISCONNECTED, "");
        }
    }

    @SuppressLint("MissingPermission")
    @SuppressWarnings("deprecation")
    private void handleServices(BluetoothGatt callbackGatt, int status) {
        if (callbackGatt != gatt) return;
        if (status != BluetoothGatt.GATT_SUCCESS) {
            fail("Service discovery failed: " + status);
            return;
        }
        writeCharacteristic = chooseWritable(callbackGatt);
        if (writeCharacteristic == null) {
            fail("No writable BLE characteristic was found.");
            return;
        }
        int properties = writeCharacteristic.getProperties();
        writeWithResponse = (properties & BluetoothGattCharacteristic.PROPERTY_WRITE) != 0;
        BluetoothGattCharacteristic notify = chooseNotifiable(callbackGatt, writeCharacteristic);
        if (notify == null) {
            markReady("write only");
            return;
        }
        try {
            if (!callbackGatt.setCharacteristicNotification(notify, true)) {
                markReady("write only");
                return;
            }
            BluetoothGattDescriptor descriptor = notify.getDescriptor(CCCD);
            if (descriptor == null) {
                markReady("write only");
                return;
            }
            byte[] enable = (notify.getProperties() & BluetoothGattCharacteristic.PROPERTY_INDICATE) != 0
                    ? BluetoothGattDescriptor.ENABLE_INDICATION_VALUE
                    : BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE;
            boolean started;
            if (Build.VERSION.SDK_INT >= 33) {
                started = callbackGatt.writeDescriptor(descriptor, enable) == BluetoothStatusCodes.SUCCESS;
            } else {
                descriptor.setValue(enable);
                started = callbackGatt.writeDescriptor(descriptor);
            }
            if (!started) markReady("write only");
        } catch (SecurityException exception) {
            fail("Bluetooth permission was lost.");
        }
    }

    @SuppressLint("MissingPermission")
    @SuppressWarnings("deprecation")
    private void pumpWrites() {
        if (!ready || writeInFlight || writeQueue.isEmpty() || gatt == null || writeCharacteristic == null) return;
        PendingWrite pending = writeQueue.peekFirst();
        if (pending == null) return;
        byte[] value = pending.value;
        int writeType = writeWithResponse
                ? BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                : BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE;
        boolean started;
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                started = gatt.writeCharacteristic(writeCharacteristic, value, writeType)
                        == BluetoothStatusCodes.SUCCESS;
            } else {
                writeCharacteristic.setWriteType(writeType);
                writeCharacteristic.setValue(value);
                started = gatt.writeCharacteristic(writeCharacteristic);
            }
        } catch (SecurityException exception) {
            started = false;
        }
        if (!started) {
            writeQueue.clear();
            writeInFlight = false;
            fail("BLE write did not start.");
            return;
        }
        if (writeWithResponse) {
            writeInFlight = true;
        } else {
            writeQueue.poll();
            main.postDelayed(this::pumpWrites, NO_RESPONSE_PACING_MS);
        }
    }

    private void handleWrite(BluetoothGatt callbackGatt, int status) {
        if (callbackGatt != gatt || !writeWithResponse || !writeInFlight) return;
        writeInFlight = false;
        if (status != BluetoothGatt.GATT_SUCCESS) {
            writeQueue.clear();
            fail("BLE write failed: " + status);
            return;
        }
        writeQueue.poll();
        pumpWrites();
    }

    private void consumeIncoming(byte[] bytes) {
        for (byte raw : bytes) {
            int value = raw & 0xff;
            if (value == '\r') continue;
            if (value == '\n') {
                if (incoming.length() > 0) {
                    listener.onBleLine(incoming.toString());
                    incoming.setLength(0);
                }
            } else if (value >= 32 && value <= 126) {
                if (incoming.length() < 128) incoming.append((char) value);
                else incoming.setLength(0);
            }
        }
    }

    private static BluetoothGattCharacteristic chooseWritable(BluetoothGatt activeGatt) {
        BluetoothGattCharacteristic fallback = null;
        for (BluetoothGattService service : activeGatt.getServices()) {
            for (BluetoothGattCharacteristic characteristic : service.getCharacteristics()) {
                int properties = characteristic.getProperties();
                boolean writable = (properties & (BluetoothGattCharacteristic.PROPERTY_WRITE |
                        BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE)) != 0;
                if (!writable) continue;
                if (uuidEndsWith(characteristic.getUuid(), "ffe1")) return characteristic;
                if (fallback == null) fallback = characteristic;
            }
        }
        return fallback;
    }

    private static BluetoothGattCharacteristic chooseNotifiable(BluetoothGatt activeGatt,
                                                                  BluetoothGattCharacteristic preferred) {
        int preferredProperties = preferred.getProperties();
        if ((preferredProperties & (BluetoothGattCharacteristic.PROPERTY_NOTIFY |
                BluetoothGattCharacteristic.PROPERTY_INDICATE)) != 0) return preferred;
        BluetoothGattService owner = preferred.getService();
        if (owner != null) {
            for (BluetoothGattCharacteristic characteristic : owner.getCharacteristics()) {
                int properties = characteristic.getProperties();
                if ((properties & (BluetoothGattCharacteristic.PROPERTY_NOTIFY |
                        BluetoothGattCharacteristic.PROPERTY_INDICATE)) != 0) return characteristic;
            }
        }
        for (BluetoothGattService service : activeGatt.getServices()) {
            for (BluetoothGattCharacteristic characteristic : service.getCharacteristics()) {
                int properties = characteristic.getProperties();
                if ((properties & (BluetoothGattCharacteristic.PROPERTY_NOTIFY |
                        BluetoothGattCharacteristic.PROPERTY_INDICATE)) != 0) return characteristic;
            }
        }
        return null;
    }

    private static boolean uuidEndsWith(UUID uuid, String shortUuid) {
        return uuid.toString().toLowerCase(Locale.ROOT).startsWith("0000" + shortUuid.toLowerCase(Locale.ROOT));
    }

    private void markReady(String detail) {
        ready = true;
        listener.onBleState(State.READY, detail);
        pumpWrites();
    }

    private void fail(String detail) {
        ready = false;
        listener.onBleState(State.ERROR, detail);
        closeInternal();
    }

    @SuppressLint("MissingPermission")
    private void closeInternal() {
        ready = false;
        writeQueue.clear();
        writeInFlight = false;
        writeCharacteristic = null;
        incoming.setLength(0);
        if (gatt != null) {
            try { gatt.close(); } catch (RuntimeException ignored) { }
            gatt = null;
        }
    }

    @SuppressLint("MissingPermission")
    private static String safeName(BluetoothDevice device) {
        try {
            String name = device.getName();
            return name == null || name.isEmpty() ? "BLE device" : name;
        } catch (SecurityException exception) {
            return "BLE device";
        }
    }
}
