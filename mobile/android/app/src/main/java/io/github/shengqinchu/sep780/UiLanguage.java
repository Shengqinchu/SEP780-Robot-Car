package io.github.shengqinchu.sep780;

import java.util.Locale;

final class UiLanguage {
    static final String ENGLISH = "en";
    static final String SIMPLIFIED_CHINESE = "zh-CN";

    private UiLanguage() { }

    static String resolve(String requested, Locale fallback) {
        if (requested != null && requested.toLowerCase(Locale.ROOT).startsWith("zh")) {
            return SIMPLIFIED_CHINESE;
        }
        if (requested != null && requested.toLowerCase(Locale.ROOT).startsWith("en")) {
            return ENGLISH;
        }
        return fallback != null && fallback.getLanguage().equalsIgnoreCase("zh")
                ? SIMPLIFIED_CHINESE : ENGLISH;
    }

    static Locale localeFor(String language) {
        return SIMPLIFIED_CHINESE.equals(language) ? Locale.SIMPLIFIED_CHINESE : Locale.ENGLISH;
    }
}
