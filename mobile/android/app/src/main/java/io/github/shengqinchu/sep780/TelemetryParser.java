package io.github.shengqinchu.sep780;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class TelemetryParser {
    private static final Pattern FRAME = Pattern.compile(
            "SEP780 v=1 ms=(\\d{1,10}) mode=([0-2]) state=(\\d{1,2}) owner=([01]) " +
            "line=([0-7]) mm=(\\d{1,4}) mv=(\\d{1,5}) l=(-?\\d{1,3}) r=(-?\\d{1,3})");
    private static final String[] MODES = {"idle", "line", "manual"};
    private static final String[] STATES = {
            "idle", "ready", "following", "manual", "obstacle", "clear_wait", "line_lost",
            "ambiguous_line", "sensor_fault", "low_battery", "remote_timeout", "command_error",
            "stopped", "bad_config"
    };

    public static final class Telemetry {
        public final String mode;
        public final String state;
        public final int lineBits;
        public final int rangeMm;
        public final int batteryMv;
        public final int leftPwm;
        public final int rightPwm;

        private Telemetry(String mode, String state, int lineBits, int rangeMm,
                          int batteryMv, int leftPwm, int rightPwm) {
            this.mode = mode;
            this.state = state;
            this.lineBits = lineBits;
            this.rangeMm = rangeMm;
            this.batteryMv = batteryMv;
            this.leftPwm = leftPwm;
            this.rightPwm = rightPwm;
        }
    }

    private TelemetryParser() {}

    public static Telemetry parse(String line) {
        Matcher match = FRAME.matcher(line == null ? "" : line);
        if (!match.matches()) return null;
        int mode = Integer.parseInt(match.group(2));
        int state = Integer.parseInt(match.group(3));
        int bits = Integer.parseInt(match.group(5));
        int range = Integer.parseInt(match.group(6));
        int battery = Integer.parseInt(match.group(7));
        int left = Integer.parseInt(match.group(8));
        int right = Integer.parseInt(match.group(9));
        if (state >= STATES.length || range > 4000 || battery > 20000 ||
                Math.abs(left) > 180 || Math.abs(right) > 180) return null;
        return new Telemetry(MODES[mode], STATES[state], bits, range, battery, left, right);
    }
}
