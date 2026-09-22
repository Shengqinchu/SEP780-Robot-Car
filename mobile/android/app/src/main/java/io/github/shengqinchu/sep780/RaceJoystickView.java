package io.github.shengqinchu.sep780;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.RectF;
import android.util.AttributeSet;
import android.view.HapticFeedbackConstants;
import android.view.MotionEvent;
import android.view.View;

/** Large analog throttle/steering control with live differential-drive feedback. */
public final class RaceJoystickView extends View {
    public interface Listener {
        void onDriveStart(float throttle, float steering);
        void onDriveChanged(float throttle, float steering);
        void onDriveEnd();
    }

    private final Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint stroke = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint text = new Paint(Paint.ANTI_ALIAS_FLAG);
    private Listener listener;
    private float throttle;
    private float steering;
    private boolean active;
    private int maxPwm = RobotProtocol.DEFAULT_PWM;
    private int leftPwm;
    private int rightPwm;

    public RaceJoystickView(Context context, AttributeSet attributes) {
        super(context, attributes);
        setClickable(true);
        setFocusable(true);
        stroke.setStyle(Paint.Style.STROKE);
        stroke.setStrokeCap(Paint.Cap.ROUND);
        text.setTextAlign(Paint.Align.CENTER);
        updateDescription();
    }

    public void setListener(Listener listener) {
        this.listener = listener;
    }

    public void setMaxPwm(int maxPwm) {
        this.maxPwm = maxPwm;
        updateDescription();
        invalidate();
    }

    public void setTelemetry(int leftPwm, int rightPwm) {
        this.leftPwm = leftPwm;
        this.rightPwm = rightPwm;
        updateDescription();
        invalidate();
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        float density = getResources().getDisplayMetrics().density;
        float cx = getWidth() * 0.5f;
        float cy = getHeight() * 0.5f;
        float radius = Math.max(0.0f, Math.min(getWidth(), getHeight()) * 0.5f - 12.0f * density);
        float travel = radius * 0.66f;

        fill.setColor(getContext().getColor(R.color.dashboard));
        canvas.drawCircle(cx, cy, radius, fill);

        stroke.setColor(getContext().getColor(R.color.dashboard_track));
        stroke.setStrokeWidth(1.5f * density);
        canvas.drawCircle(cx, cy, travel, stroke);
        canvas.drawCircle(cx, cy, travel * 0.55f, stroke);
        canvas.drawLine(cx - travel, cy, cx + travel, cy, stroke);
        canvas.drawLine(cx, cy - travel, cx, cy + travel, stroke);

        RectF steeringArc = new RectF(cx - travel, cy - travel, cx + travel, cy + travel);
        stroke.setColor(getContext().getColor(R.color.joystick_steering));
        stroke.setStrokeWidth(5.0f * density);
        canvas.drawArc(steeringArc, 205.0f, 130.0f, false, stroke);
        stroke.setColor(getContext().getColor(R.color.joystick_throttle));
        canvas.drawArc(steeringArc, -65.0f, 130.0f, false, stroke);

        float thumbX = cx + steering * travel;
        float thumbY = cy - throttle * travel;
        fill.setColor(getContext().getColor(
                active ? R.color.joystick_thumb_active : R.color.joystick_thumb));
        canvas.drawCircle(thumbX, thumbY, radius * 0.18f, fill);
        stroke.setColor(getContext().getColor(R.color.band));
        stroke.setStrokeWidth(2.0f * density);
        canvas.drawCircle(thumbX, thumbY, radius * 0.18f, stroke);

        text.setColor(getContext().getColor(R.color.dashboard_text));
        text.setTextSize(13.0f * density);
        text.setFakeBoldText(true);
        canvas.drawText(getContext().getString(R.string.joystick_limit, maxPwm),
                cx, cy - radius * 0.78f, text);
        text.setColor(getContext().getColor(R.color.dashboard_muted));
        text.setTextSize(11.0f * density);
        text.setFakeBoldText(false);
        canvas.drawText(getContext().getString(R.string.joystick_output, leftPwm, rightPwm),
                cx, cy + radius * 0.83f, text);

        if (!isEnabled()) {
            fill.setColor(0x77000000);
            canvas.drawCircle(cx, cy, radius, fill);
        }
    }

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        if (!isEnabled()) return false;
        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                active = true;
                getParent().requestDisallowInterceptTouchEvent(true);
                performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP);
                updatePosition(event.getX(), event.getY());
                if (listener != null) listener.onDriveStart(throttle, steering);
                return true;
            case MotionEvent.ACTION_MOVE:
                if (!active) return false;
                updatePosition(event.getX(), event.getY());
                if (listener != null) listener.onDriveChanged(throttle, steering);
                return true;
            case MotionEvent.ACTION_UP:
                if (!active) return false;
                releaseControl();
                performClick();
                return true;
            case MotionEvent.ACTION_CANCEL:
                if (!active) return false;
                releaseControl();
                return true;
            default:
                return true;
        }
    }

    @Override
    public boolean performClick() {
        super.performClick();
        return true;
    }

    private void updatePosition(float x, float y) {
        float cx = getWidth() * 0.5f;
        float cy = getHeight() * 0.5f;
        float density = getResources().getDisplayMetrics().density;
        float radius = Math.max(1.0f, Math.min(getWidth(), getHeight()) * 0.5f - 12.0f * density);
        float travel = Math.max(1.0f, radius * 0.66f);
        float dx = x - cx;
        float dy = y - cy;
        float length = (float) Math.hypot(dx, dy);
        if (length > travel) {
            dx = dx / length * travel;
            dy = dy / length * travel;
        }
        steering = dx / travel;
        throttle = -dy / travel;
        invalidate();
    }

    private void releaseControl() {
        active = false;
        throttle = 0.0f;
        steering = 0.0f;
        getParent().requestDisallowInterceptTouchEvent(false);
        if (listener != null) listener.onDriveEnd();
        invalidate();
    }

    private void updateDescription() {
        setContentDescription(getContext().getString(R.string.joystick_accessibility,
                maxPwm, leftPwm, rightPwm));
    }
}
