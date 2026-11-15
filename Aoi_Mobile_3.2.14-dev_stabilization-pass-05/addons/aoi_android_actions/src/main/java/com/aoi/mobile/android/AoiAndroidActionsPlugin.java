package com.aoi.mobile.android;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.provider.AlarmClock;
import android.provider.CalendarContract;
import android.text.TextUtils;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

import java.util.Arrays;
import java.util.Calendar;
import java.util.List;
import java.util.TimeZone;

public final class AoiAndroidActionsPlugin extends GodotPlugin {
    public AoiAndroidActionsPlugin(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "AoiAndroidActions";
    }

    @Override
    public List<String> getPluginMethods() {
        return Arrays.asList("setAlarm", "addCalendarEvent");
    }

    @UsedByGodot
    public boolean setAlarm(int hour, int minute, String label) {
        if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
            return false;
        }
        Activity activity = getActivity();
        if (activity == null) {
            return false;
        }
        Intent intent = new Intent(AlarmClock.ACTION_SET_ALARM);
        intent.putExtra(AlarmClock.EXTRA_HOUR, hour);
        intent.putExtra(AlarmClock.EXTRA_MINUTES, minute);
        intent.putExtra(AlarmClock.EXTRA_MESSAGE, label == null ? "" : label);
        intent.putExtra(AlarmClock.EXTRA_SKIP_UI, false);
        try {
            activity.startActivity(intent);
            return true;
        } catch (ActivityNotFoundException | SecurityException error) {
            return false;
        }
    }

    @UsedByGodot
    public boolean addCalendarEvent(
            String title,
            int year,
            int month,
            int day,
            int hour,
            int minute,
            int durationMinutes,
            String description,
            String location) {
        if (TextUtils.isEmpty(title) || year < 2020 || year > 2100
                || month < 1 || month > 12 || day < 1 || day > 31
                || hour < 0 || hour > 23 || minute < 0 || minute > 59
                || durationMinutes < 1 || durationMinutes > 1440) {
            return false;
        }
        Activity activity = getActivity();
        if (activity == null) {
            return false;
        }

        Calendar start = Calendar.getInstance();
        start.setLenient(false);
        start.clear();
        start.set(year, month - 1, day, hour, minute);
        final long startMillis;
        try {
            startMillis = start.getTimeInMillis();
        } catch (IllegalArgumentException error) {
            return false;
        }

        Intent intent = new Intent(Intent.ACTION_INSERT);
        intent.setData(CalendarContract.Events.CONTENT_URI);
        intent.putExtra(CalendarContract.Events.TITLE, title);
        intent.putExtra(CalendarContract.Events.DESCRIPTION, description == null ? "" : description);
        intent.putExtra(CalendarContract.Events.EVENT_LOCATION, location == null ? "" : location);
        intent.putExtra(CalendarContract.Events.DTSTART, startMillis);
        intent.putExtra(CalendarContract.Events.DTEND, startMillis + durationMinutes * 60_000L);
        intent.putExtra(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getDefault().getID());
        try {
            activity.startActivity(intent);
            return true;
        } catch (ActivityNotFoundException | SecurityException error) {
            return false;
        }
    }
}
