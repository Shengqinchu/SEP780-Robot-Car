package io.github.shengqinchu.sep780;

import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

/** Maps a deliberately small bilingual vocabulary to bounded robot actions. */
public final class VoiceCommandParser {
    public enum Action { STOP, LINE, FORWARD, BACKWARD, LEFT, RIGHT, UNKNOWN }

    private static final Set<String> LINE = words(
            "循迹", "开始循迹", "自动循迹", "跟线", "开始跟线",
            "line", "followline", "linefollow", "startline");
    private static final Set<String> FORWARD = words(
            "前进", "向前", "向前走", "往前走", "forward", "goforward");
    private static final Set<String> BACKWARD = words(
            "后退", "倒车", "向后", "向后退", "back", "backward", "goback");
    private static final Set<String> LEFT = words(
            "左转", "向左", "向左转", "left", "turnleft");
    private static final Set<String> RIGHT = words(
            "右转", "向右", "向右转", "right", "turnright");
    private static final Set<String> STOP = words(
            "停止", "停车", "停下", "紧急停止", "别动",
            "stop", "halt", "emergencystop");

    private VoiceCommandParser() {}

    public static Action parse(String phrase) {
        String value = normalize(phrase);
        if (isStop(value)) return Action.STOP;
        if (LINE.contains(value)) return Action.LINE;
        if (FORWARD.contains(value)) return Action.FORWARD;
        if (BACKWARD.contains(value)) return Action.BACKWARD;
        if (LEFT.contains(value)) return Action.LEFT;
        if (RIGHT.contains(value)) return Action.RIGHT;
        return Action.UNKNOWN;
    }

    public static Action parseCandidates(List<String> candidates) {
        if (candidates == null) return Action.UNKNOWN;
        // A stop hypothesis always wins over a movement hypothesis.
        for (String candidate : candidates) {
            if (isStop(normalize(candidate))) return Action.STOP;
        }
        for (String candidate : candidates) {
            Action action = parse(candidate);
            if (action != Action.UNKNOWN) return action;
        }
        return Action.UNKNOWN;
    }

    static String normalize(String phrase) {
        if (phrase == null) return "";
        return phrase.toLowerCase(Locale.ROOT).replaceAll("[\\s\\p{P}\\p{S}]+", "");
    }

    private static boolean isStop(String value) {
        // False positives stop the car; they never start motion.
        return STOP.contains(value) || value.contains("停") || value.contains("stop") || value.contains("halt");
    }

    private static Set<String> words(String... values) {
        return new HashSet<>(Arrays.asList(values));
    }
}
