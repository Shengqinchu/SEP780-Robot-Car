package io.github.shengqinchu.sep780;

import org.junit.Test;

import static org.junit.Assert.assertEquals;

public final class DriveSlewLimiterTest {
    @Test
    public void launchesAtThresholdThenRampsAndDecelerates() {
        DriveSlewLimiter limiter = new DriveSlewLimiter();
        assertWheels(110, 110, limiter.step(new DriveMixer.Wheels(200, 200)));
        assertWheels(125, 125, limiter.step(new DriveMixer.Wheels(200, 200)));
        assertWheels(95, 95, limiter.step(new DriveMixer.Wheels(0, 0)));
    }

    @Test
    public void directionReversalPassesThroughNeutral() {
        DriveSlewLimiter limiter = new DriveSlewLimiter();
        limiter.step(new DriveMixer.Wheels(200, 200));
        assertWheels(0, 0, limiter.step(new DriveMixer.Wheels(-200, -200)));
        assertWheels(-110, -110, limiter.step(new DriveMixer.Wheels(-200, -200)));
    }

    @Test
    public void resetRestoresColdStartBehavior() {
        DriveSlewLimiter limiter = new DriveSlewLimiter();
        limiter.step(new DriveMixer.Wheels(200, 200));
        limiter.step(new DriveMixer.Wheels(200, 200));
        limiter.reset();
        assertWheels(110, 110, limiter.step(new DriveMixer.Wheels(200, 200)));
    }

    private static void assertWheels(int left, int right, DriveMixer.Wheels actual) {
        assertEquals(left, actual.left);
        assertEquals(right, actual.right);
    }
}
