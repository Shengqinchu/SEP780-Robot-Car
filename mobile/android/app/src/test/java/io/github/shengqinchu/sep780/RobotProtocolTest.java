package io.github.shengqinchu.sep780;

import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertThrows;

public final class RobotProtocolTest {
    @Test
    public void encodesProjectWireFormatWithFreshSequences() {
        RobotProtocol protocol = new RobotProtocol();
        assertEquals("S 1 STOP\n", protocol.stop());
        assertEquals("S 2 SPEED 50\n", protocol.speed(50));
        assertEquals("S 3 LINE PULSE\n", protocol.linePulse());
        assertEquals("S 4 LINE CONTINUOUS\n", protocol.lineContinuous());
        assertEquals("S 5 LINE HYBRID\n", protocol.lineHybrid());
        assertEquals("S 6 ARM LINE\n", protocol.armLine());
        assertEquals("S 7 PING\n", protocol.ping());
        assertEquals("S 8 ARM MANUAL\n", protocol.armManual());
        assertEquals("S 9 DRIVE 200 -200\n", protocol.drive(200, -200));
        assertEquals("S 10 R -200 200\n", protocol.remoteDrive(-200, 200));
        assertEquals("S 11 H 1\n", protocol.horn(true));
        assertEquals("S 12 H 0\n", protocol.horn(false));
        assertEquals("S 13 STATUS\n", protocol.status());
    }

    @Test
    public void rejectsPwmOutsideTheFirmwareLimit() {
        RobotProtocol protocol = new RobotProtocol();
        assertThrows(IllegalArgumentException.class, () -> protocol.drive(201, 0));
        assertThrows(IllegalArgumentException.class, () -> protocol.drive(0, -201));
        assertThrows(IllegalArgumentException.class, () -> protocol.remoteDrive(201, 0));
        assertThrows(IllegalArgumentException.class, () -> protocol.remoteDrive(0, -201));
        assertThrows(IllegalArgumentException.class, () -> protocol.speed(40));
        assertThrows(IllegalArgumentException.class, () -> protocol.speed(55));
        assertThrows(IllegalArgumentException.class, () -> protocol.speed(201));
    }

    @Test
    public void remoteUiCeilingMatchesTheMotorIoCapWithoutChangingTheWireRange() {
        assertEquals(180, RobotProtocol.REMOTE_MAX_PWM);
        assertEquals(200, RobotProtocol.MAX_PWM);
    }
}
