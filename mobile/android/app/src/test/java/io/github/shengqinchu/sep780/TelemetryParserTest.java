package io.github.shengqinchu.sep780;

import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

public final class TelemetryParserTest {
    @Test
    public void parsesAValidFirmwareFrame() {
        TelemetryParser.Telemetry value = TelemetryParser.parse(
                "SEP780 v=1 ms=1200 mode=1 state=2 owner=0 line=2 mm=800 mv=7400 l=100 r=50");
        assertEquals("line", value.mode);
        assertEquals("following", value.state);
        assertEquals(2, value.lineBits);
        assertEquals(800, value.rangeMm);
        assertEquals(7400, value.batteryMv);
        assertEquals(100, value.leftPwm);
        assertEquals(50, value.rightPwm);
    }

    @Test
    public void rejectsMalformedOrOutOfRangeFrames() {
        assertNull(TelemetryParser.parse("ACK 1"));
        assertNull(TelemetryParser.parse(
                "SEP780 v=1 ms=1 mode=1 state=99 owner=0 line=2 mm=800 mv=7400 l=0 r=0"));
    }
}
