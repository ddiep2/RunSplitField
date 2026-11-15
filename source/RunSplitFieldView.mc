import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.UserProfile;
import Toybox.WatchUi;

// One full-screen data field: heart rate (colored by zone) on top,
// pace in the middle, and time left in the current workout step on the bottom.
// If no timed workout step is active, the bottom shows total timer instead.
class RunSplitFieldView extends WatchUi.DataField {

    hidden var mHeartRate as Number or Null = null;
    hidden var mSpeed as Float or Null = null;            // meters per second
    hidden var mTimerMs as Number = 0;                    // total activity timer in ms
    hidden var mStepStartMs as Number = 0;                // timer value when the current step began
    hidden var mStepDurationSec as Number or Null = null; // planned length of the current step
    hidden var mStepKey as String = "";                   // used to detect when the step changes
    hidden var mZones as Array<Number> or Null = null;    // [z1 min, z1 max, z2 max, z3 max, z4 max, z5 max]

    function initialize() {
        DataField.initialize();
        mZones = UserProfile.getHeartRateZones(UserProfile.getCurrentSport());
        System.println("Zones: " + mZones);
    }

    // Called about once per second with the latest activity data.
    function compute(info as Activity.Info) as Void {
        mHeartRate = info.currentHeartRate;
        mSpeed = info.currentSpeed;
        var t = info.timerTime;
        mTimerMs = (t != null) ? t : 0;
        updateStep();
    }

    // The API gives the current step's planned duration but not how long
    // we've been in it, so we record the timer value whenever the step changes.
    hidden function updateStep() as Void {
        mStepDurationSec = null;
        if (!(Activity has :getCurrentWorkoutStep)) {
            return;
        }
        var stepInfo = Activity.getCurrentWorkoutStep();
        if (stepInfo == null) {
            mStepKey = "";
            return;
        }

        var raw = stepInfo.step;
        var step = null;
        if (raw instanceof Activity.WorkoutIntervalStep) {
            step = raw.activeStep;
        } else if (raw instanceof Activity.WorkoutStep) {
            step = raw;
        }

        if (step != null && step.durationType == Activity.WORKOUT_STEP_DURATION_TIME) {
            mStepDurationSec = step.durationValue;
        }

        var key = "" + stepInfo.name + "|" + stepInfo.intensity + "|" + mStepDurationSec;
        if (!key.equals(mStepKey)) {
            mStepKey = key;
            mStepStartMs = mTimerMs;
            // Check the Debug Console to confirm durationValue is in seconds.
            System.println("New step: " + key);
        }
    }

    // Step changes on Garmin also create a lap, so this catches back-to-back
    // steps that look identical (like repeated intervals).
    function onTimerLap() as Void {
        mStepStartMs = mTimerMs;
    }

    function onTimerReset() as Void {
        mStepStartMs = 0;
        mStepKey = "";
    }

    function onUpdate(dc as Dc) as Void {
        var bg = getBackgroundColor();
        var fg = (bg == Graphics.COLOR_BLACK) ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
        dc.setColor(fg, bg);
        dc.clear();

        var cx = dc.getWidth() / 2;
        var h = dc.getHeight();
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        // Heart rate number, with a zone-colored dot to its left
        var hr = mHeartRate;
        var hrText = (hr == null) ? "--" : hr.toString();
        var hrY = h * 0.24;
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, hrY, Graphics.FONT_NUMBER_MEDIUM, hrText, center);
        var dotColor = zoneColor(hr, Graphics.COLOR_TRANSPARENT);
        if (dotColor != Graphics.COLOR_TRANSPARENT) {
            var textW = dc.getTextWidthInPixels(hrText, Graphics.FONT_NUMBER_MEDIUM);
            dc.setColor(dotColor, Graphics.COLOR_TRANSPARENT);
            drawHeart(dc, cx - textW / 2 - 16, hrY - 2, 5);
        }

        // Pace
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.48, Graphics.FONT_NUMBER_MEDIUM, formatPace(mSpeed), center);

        // Step time left, or total time when there's no timed step
        var label = "TIME";
        var secs = mTimerMs / 1000;
        var stepDur = mStepDurationSec;
        if (stepDur != null) {
            label = "STEP LEFT";
            secs = stepDur - (mTimerMs - mStepStartMs) / 1000;
        }
        dc.drawText(cx, h * 0.70, Graphics.FONT_NUMBER_MEDIUM, formatTime(secs), center);
        dc.drawText(cx, h * 0.86, Graphics.FONT_XTINY, label, center);
    }

    hidden function zoneColor(hr as Number or Null, fallback as Number) as Number {
        var zones = mZones;
        if (hr == null || zones == null || hr < zones[0]) {
            return fallback;
        }
        if (hr <= zones[1]) { return Graphics.COLOR_DK_GRAY; } // zone 1
        if (hr <= zones[2]) { return Graphics.COLOR_BLUE; }    // zone 2
        if (hr <= zones[3]) { return Graphics.COLOR_GREEN; }   // zone 3
        if (hr <= zones[4]) { return Graphics.COLOR_ORANGE; }  // zone 4
        return Graphics.COLOR_RED;                             // zone 5
    }

    // Two circles on top plus a triangle underneath make a heart shape.
    hidden function drawHeart(dc as Dc, x as Numeric, y as Numeric, r as Number) as Void {
        dc.fillCircle(x - r, y - r / 2, r);
        dc.fillCircle(x + r, y - r / 2, r);
        dc.fillPolygon([[x - 2 * r, y], [x + 2 * r, y], [x, y + 2 * r + 2]]);
    }

    hidden function formatPace(speed as Float or Null) as String {
        if (speed == null || speed < 0.5) {
            return "--:--";
        }
        var meters = (System.getDeviceSettings().paceUnits == System.UNIT_STATUTE) ? 1609.344 : 1000.0;
        var secPerUnit = (meters / speed).toNumber();
        return (secPerUnit / 60).format("%d") + ":" + (secPerUnit % 60).format("%02d");
    }

    hidden function formatTime(secs as Number) as String {
        if (secs < 0) {
            secs = 0;
        }
        var hrs = secs / 3600;
        var mins = (secs % 3600) / 60;
        var s = secs % 60;
        if (hrs > 0) {
            return hrs.format("%d") + ":" + mins.format("%02d") + ":" + s.format("%02d");
        }
        return mins.format("%d") + ":" + s.format("%02d");
    }
}