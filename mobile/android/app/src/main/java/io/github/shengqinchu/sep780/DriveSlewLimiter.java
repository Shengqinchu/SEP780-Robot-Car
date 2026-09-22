package io.github.shengqinchu.sep780;

/** Adds a bounded launch step, acceleration ramp, and neutral reversal frame. */
public final class DriveSlewLimiter {
    private static final int ACCEL_STEP = 15;
    private static final int DECEL_STEP = 30;
    private int left;
    private int right;

    public DriveMixer.Wheels step(DriveMixer.Wheels target) {
        left = stepWheel(left, target.left);
        right = stepWheel(right, target.right);
        return new DriveMixer.Wheels(left, right);
    }

    public void reset() {
        left = 0;
        right = 0;
    }

    private static int stepWheel(int current, int target) {
        if (target == 0) return moveToward(current, 0, DECEL_STEP);
        if (current != 0 && Integer.signum(current) != Integer.signum(target)) return 0;
        if (current == 0) {
            int launch = Math.min(Math.abs(target), DriveMixer.START_PWM);
            return Integer.signum(target) * launch;
        }
        int step = Math.abs(target) > Math.abs(current) ? ACCEL_STEP : DECEL_STEP;
        return moveToward(current, target, step);
    }

    private static int moveToward(int current, int target, int step) {
        if (current < target) return Math.min(target, current + step);
        if (current > target) return Math.max(target, current - step);
        return current;
    }
}
