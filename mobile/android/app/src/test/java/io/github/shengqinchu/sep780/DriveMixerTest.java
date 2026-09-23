package io.github.shengqinchu.sep780;

import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

public final class DriveMixerTest {
    @Test
    public void centerAndDeadZoneStopBothWheels() {
        assertWheels(0, 0, DriveMixer.mix(0.0f, 0.0f, 150));
        assertWheels(0, 0, DriveMixer.mix(0.08f, -0.10f, 150));
    }

    @Test
    public void fullAxesMapToDifferentialDrive() {
        assertWheels(180, 180, DriveMixer.mix(1.0f, 0.0f, 180));
        assertWheels(-180, -180, DriveMixer.mix(-1.0f, 0.0f, 180));
        assertWheels(180, -180, DriveMixer.mix(0.0f, 1.0f, 180));
        assertWheels(-180, 180, DriveMixer.mix(0.0f, -1.0f, 180));
        assertWheels(180, 0, DriveMixer.mix(1.0f, 1.0f, 180));
    }

    @Test
    public void motionDemandStartsAtTheMeasuredMotorThreshold() {
        DriveMixer.Wheels wheels = DriveMixer.mix(0.09f, 0.0f, 180);
        assertTrue(Math.abs(wheels.left) >= DriveMixer.START_PWM);
        assertTrue(Math.abs(wheels.right) >= DriveMixer.START_PWM);
    }

    @Test
    public void validatesAndClampsInputs() {
        assertThrows(IllegalArgumentException.class, () -> DriveMixer.mix(0.0f, 0.0f, 109));
        assertThrows(IllegalArgumentException.class, () -> DriveMixer.mix(0.0f, 0.0f, 181));
        assertWheels(180, 180, DriveMixer.mix(2.0f, 0.0f, 180));
    }

    private static void assertWheels(int left, int right, DriveMixer.Wheels actual) {
        assertEquals(left, actual.left);
        assertEquals(right, actual.right);
    }
}
