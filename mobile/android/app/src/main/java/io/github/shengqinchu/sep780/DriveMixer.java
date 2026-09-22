package io.github.shengqinchu.sep780;

/** Pure differential-drive mixing used by the touch controller and unit tests. */
public final class DriveMixer {
    public static final float THROTTLE_DEAD_ZONE = 0.08f;
    public static final float STEERING_DEAD_ZONE = 0.10f;
    public static final int START_PWM = 110;

    public static final class Wheels {
        public final int left;
        public final int right;

        Wheels(int left, int right) {
            this.left = left;
            this.right = right;
        }
    }

    private DriveMixer() {}

    public static Wheels mix(float throttle, float steering, int limitPwm) {
        if (limitPwm < START_PWM || limitPwm > RobotProtocol.MAX_PWM) {
            throw new IllegalArgumentException("Unsupported remote PWM limit.");
        }
        float shapedThrottle = shape(applyDeadZone(clamp(throttle), THROTTLE_DEAD_ZONE), 0.35f);
        float shapedSteering = shape(applyDeadZone(clamp(steering), STEERING_DEAD_ZONE), 0.50f);
        float left = shapedThrottle + shapedSteering;
        float right = shapedThrottle - shapedSteering;
        float normalization = Math.max(1.0f, Math.max(Math.abs(left), Math.abs(right)));
        left /= normalization;
        right /= normalization;
        float demand = Math.max(Math.abs(left), Math.abs(right));
        if (demand == 0.0f) return new Wheels(0, 0);

        int dominant = START_PWM + Math.round((limitPwm - START_PWM) * demand);
        int leftPwm = Math.round(left / demand * dominant);
        int rightPwm = Math.round(right / demand * dominant);
        return new Wheels(clampPwm(leftPwm, limitPwm), clampPwm(rightPwm, limitPwm));
    }

    private static float applyDeadZone(float value, float deadZone) {
        float magnitude = Math.abs(value);
        if (magnitude <= deadZone) return 0.0f;
        float scaled = (magnitude - deadZone) / (1.0f - deadZone);
        return Math.copySign(scaled, value);
    }

    private static float shape(float value, float linearWeight) {
        return linearWeight * value + (1.0f - linearWeight) * value * value * value;
    }

    private static float clamp(float value) {
        return Math.max(-1.0f, Math.min(1.0f, value));
    }

    private static int clampPwm(int value, int limit) {
        return Math.max(-limit, Math.min(limit, value));
    }
}
