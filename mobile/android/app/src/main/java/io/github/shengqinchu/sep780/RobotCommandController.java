package io.github.shengqinchu.sep780;

import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;

/** Schedules line-mode leases and low-latency remote-drive frames. */
public final class RobotCommandController {
    public enum Direction { FORWARD, BACKWARD, LEFT, RIGHT }
    public enum LineMode { PULSE, HYBRID }

    public interface Transport {
        boolean isReady();
        boolean sendAscii(String frame);
        boolean sendRealtimeAscii(String frame);
        boolean sendPriorityAscii(String frame);
    }

    public interface Listener {
        void onControlState(String state);
        void onFrameSent(String frame);
    }

    private static final long MODE_SWITCH_DELAY_MS = 120;
    private static final long LINE_HEARTBEAT_MS = 500;
    private static final long REMOTE_REFRESH_MS = 50;
    private static final long VOICE_PULSE_MS = 1000;
    private static final long HORN_REFRESH_MS = 1000;

    private final Handler motionHandler = new Handler(Looper.getMainLooper());
    private final Handler hornHandler = new Handler(Looper.getMainLooper());
    private final RobotProtocol protocol = new RobotProtocol();
    private final DriveSlewLimiter slewLimiter = new DriveSlewLimiter();
    private final Transport transport;
    private final Listener listener;
    private int generation;
    private int hornGeneration;
    private int selectedPwm = RobotProtocol.DEFAULT_PWM;
    private LineMode selectedLineMode = LineMode.PULSE;
    private DriveMixer.Wheels remoteTarget = new DriveMixer.Wheels(0, 0);
    private boolean remoteActive;
    private boolean hornHeld;

    public RobotCommandController(Transport transport, Listener listener) {
        this.transport = transport;
        this.listener = listener;
    }

    public void startLine() {
        if (!requireConnection()) return;
        int token = resetMotion();
        if (!sendPriority(protocol.stop()) || !send(lineModeFrame())) {
            transportDisconnected();
            return;
        }
        listener.onControlState("line_pending");
        motionHandler.postDelayed(() -> {
            if (!current(token)) return;
            if (!send(protocol.armLine())) {
                transportDisconnected();
                return;
            }
            listener.onControlState("line");
            scheduleLineHeartbeat(token);
        }, MODE_SWITCH_DELAY_MS);
    }

    public void beginRemote(float throttle, float steering) {
        if (!requireConnection()) return;
        int token = resetMotion();
        remoteActive = true;
        remoteTarget = DriveMixer.mix(throttle, steering, selectedPwm);
        listener.onControlState("manual");
        scheduleRemote(token, Long.MAX_VALUE, true);
    }

    public void updateRemote(float throttle, float steering) {
        if (!remoteActive) {
            beginRemote(throttle, steering);
            return;
        }
        remoteTarget = DriveMixer.mix(throttle, steering, selectedPwm);
    }

    public void endRemote() {
        if (!remoteActive) return;
        resetMotion();
        if (transport.isReady()) sendPriority(protocol.remoteDrive(0, 0));
        listener.onControlState("stopped");
    }

    public void voicePulse(Direction direction) {
        if (!requireConnection()) return;
        int token = resetMotion();
        remoteActive = true;
        remoteTarget = wheels(direction, selectedPwm);
        listener.onControlState("manual");
        scheduleRemote(token, SystemClock.uptimeMillis() + VOICE_PULSE_MS, true);
    }

    public void beginHorn() {
        if (!requireConnection() || hornHeld) return;
        hornHeld = true;
        int token = ++hornGeneration;
        if (!send(protocol.horn(true))) {
            transportDisconnected();
            return;
        }
        scheduleHornRefresh(token);
    }

    public void endHorn() {
        if (!hornHeld) return;
        hornHeld = false;
        ++hornGeneration;
        hornHandler.removeCallbacksAndMessages(null);
        if (transport.isReady()) send(protocol.horn(false));
    }

    public void selectSpeed(int pwm) {
        if (pwm < RobotProtocol.MIN_PWM || pwm > RobotProtocol.MAX_PWM ||
                (pwm - RobotProtocol.MIN_PWM) % RobotProtocol.PWM_STEP != 0) {
            throw new IllegalArgumentException("Unsupported speed step.");
        }
        resetMotion();
        selectedPwm = pwm;
        if (transport.isReady()) sendPriority(protocol.stop());
        resetHorn(false);
        listener.onControlState("speed_selected");
    }

    public int selectedPwm() {
        return selectedPwm;
    }

    public void selectLineMode(LineMode mode) {
        if (mode == null) throw new IllegalArgumentException("Line mode is required.");
        resetMotion();
        selectedLineMode = mode;
        if (transport.isReady() &&
                (!sendPriority(protocol.stop()) || !send(lineModeFrame()))) {
            transportDisconnected();
            return;
        }
        resetHorn(false);
        listener.onControlState("line_mode_selected");
    }

    public LineMode selectedLineMode() {
        return selectedLineMode;
    }

    public void stop() {
        resetMotion();
        resetHorn(false);
        if (transport.isReady()) sendPriority(protocol.stop());
        listener.onControlState("stopped");
    }

    public void requestStatus() {
        if (requireConnection()) send(protocol.status());
    }

    public void commandRejected() {
        resetMotion();
        resetHorn(false);
        if (transport.isReady()) sendPriority(protocol.stop());
        listener.onControlState("command_error");
    }

    public void transportDisconnected() {
        resetMotion();
        resetHorn(false);
        listener.onControlState("disconnected");
    }

    public void shutdown() {
        stop();
        motionHandler.removeCallbacksAndMessages(null);
        hornHandler.removeCallbacksAndMessages(null);
    }

    private void scheduleLineHeartbeat(int token) {
        if (!current(token)) return;
        motionHandler.postDelayed(new Runnable() {
            @Override public void run() {
                if (!current(token)) return;
                if (!send(protocol.ping())) {
                    transportDisconnected();
                    return;
                }
                motionHandler.postDelayed(this, LINE_HEARTBEAT_MS);
            }
        }, LINE_HEARTBEAT_MS);
    }

    private void scheduleRemote(int token, long deadline, boolean first) {
        if (!current(token) || !remoteActive) return;
        if (SystemClock.uptimeMillis() >= deadline) {
            endRemote();
            return;
        }
        DriveMixer.Wheels output = slewLimiter.step(remoteTarget);
        String frame = protocol.remoteDrive(output.left, output.right);
        boolean sent = first ? sendPriority(frame) : sendRealtime(frame);
        if (!sent) {
            transportDisconnected();
            return;
        }
        motionHandler.postDelayed(() -> scheduleRemote(token, deadline, false), REMOTE_REFRESH_MS);
    }

    private void scheduleHornRefresh(int token) {
        hornHandler.postDelayed(new Runnable() {
            @Override public void run() {
                if (token != hornGeneration || !hornHeld || !transport.isReady()) return;
                if (!send(protocol.horn(true))) {
                    transportDisconnected();
                    return;
                }
                hornHandler.postDelayed(this, HORN_REFRESH_MS);
            }
        }, HORN_REFRESH_MS);
    }

    private boolean requireConnection() {
        if (transport.isReady()) return true;
        listener.onControlState("not_connected");
        return false;
    }

    private String lineModeFrame() {
        return selectedLineMode == LineMode.HYBRID
                ? protocol.lineHybrid() : protocol.linePulse();
    }

    private boolean send(String frame) {
        return report(frame, transport.sendAscii(frame));
    }

    private boolean sendRealtime(String frame) {
        return report(frame, transport.sendRealtimeAscii(frame));
    }

    private boolean sendPriority(String frame) {
        return report(frame, transport.sendPriorityAscii(frame));
    }

    private boolean report(String frame, boolean sent) {
        if (sent) listener.onFrameSent(frame.trim());
        return sent;
    }

    private int resetMotion() {
        ++generation;
        remoteActive = false;
        remoteTarget = new DriveMixer.Wheels(0, 0);
        slewLimiter.reset();
        motionHandler.removeCallbacksAndMessages(null);
        return generation;
    }

    private void resetHorn(boolean sendOff) {
        boolean wasHeld = hornHeld;
        hornHeld = false;
        ++hornGeneration;
        hornHandler.removeCallbacksAndMessages(null);
        if (sendOff && wasHeld && transport.isReady()) send(protocol.horn(false));
    }

    private boolean current(int token) {
        return token == generation && transport.isReady();
    }

    private static DriveMixer.Wheels wheels(Direction direction, int pwm) {
        switch (direction) {
            case FORWARD: return new DriveMixer.Wheels(pwm, pwm);
            case BACKWARD: return new DriveMixer.Wheels(-pwm, -pwm);
            case LEFT: return new DriveMixer.Wheels(-pwm, pwm);
            case RIGHT: return new DriveMixer.Wheels(pwm, -pwm);
            default: throw new IllegalArgumentException("Unsupported direction.");
        }
    }
}
