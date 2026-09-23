package io.github.shengqinchu.sep780;

import java.util.Locale;

/** Encodes the repository's newline-delimited serial protocol. */
public final class RobotProtocol {
    public static final int FIRMWARE_MIN_PWM = 50;
    public static final int MIN_PWM = 110;
    public static final int DEFAULT_PWM = 150;
    // The wire format accepts 200; this car's motor I/O clips physical writes at 180.
    public static final int MAX_PWM = 200;
    public static final int REMOTE_MAX_PWM = 180;
    public static final int PWM_STEP = 10;
    private int nextSequence = 1;

    public String stop() {
        return frame("STOP");
    }

    public String armLine() {
        return frame("ARM LINE");
    }

    public String armManual() {
        return frame("ARM MANUAL");
    }

    public String linePulse() {
        return frame("LINE PULSE");
    }

    public String lineContinuous() {
        return frame("LINE CONTINUOUS");
    }

    public String lineHybrid() {
        return frame("LINE HYBRID");
    }

    public String speed(int pwm) {
        if (pwm < FIRMWARE_MIN_PWM || pwm > MAX_PWM ||
                (pwm - FIRMWARE_MIN_PWM) % PWM_STEP != 0) {
            throw new IllegalArgumentException("Speed must be a supported PWM step.");
        }
        return frame(String.format(Locale.ROOT, "SPEED %d", pwm));
    }

    public String ping() {
        return frame("PING");
    }

    public String status() {
        return frame("STATUS");
    }

    public String drive(int left, int right) {
        if (Math.abs(left) > MAX_PWM || Math.abs(right) > MAX_PWM) {
            throw new IllegalArgumentException("Wheel PWM exceeds the project limit.");
        }
        return frame(String.format(Locale.ROOT, "DRIVE %d %d", left, right));
    }

    public String remoteDrive(int left, int right) {
        if (Math.abs(left) > MAX_PWM || Math.abs(right) > MAX_PWM) {
            throw new IllegalArgumentException("Wheel PWM exceeds the project limit.");
        }
        return frame(String.format(Locale.ROOT, "R %d %d", left, right));
    }

    public String horn(boolean active) {
        return frame(active ? "H 1" : "H 0");
    }

    private String frame(String command) {
        int sequence = nextSequence;
        nextSequence = sequence == 65535 ? 1 : sequence + 1;
        return String.format(Locale.ROOT, "S %d %s\n", sequence, command);
    }
}
