package io.github.shengqinchu.sep780;

import static org.junit.Assert.assertEquals;

import java.util.Locale;

import org.junit.Test;

public final class UiLanguageTest {
    @Test
    public void explicitChineseAndEnglishArePreserved() {
        assertEquals(UiLanguage.SIMPLIFIED_CHINESE,
                UiLanguage.resolve("zh-Hans-CN", Locale.ENGLISH));
        assertEquals(UiLanguage.ENGLISH,
                UiLanguage.resolve("en-CA", Locale.SIMPLIFIED_CHINESE));
    }

    @Test
    public void missingOrUnsupportedSelectionUsesSystemLanguage() {
        assertEquals(UiLanguage.SIMPLIFIED_CHINESE,
                UiLanguage.resolve(null, Locale.TRADITIONAL_CHINESE));
        assertEquals(UiLanguage.ENGLISH,
                UiLanguage.resolve("fr-CA", Locale.CANADA_FRENCH));
    }

    @Test
    public void languageCodesMapToStableRecognitionLocales() {
        assertEquals("zh-CN", UiLanguage.localeFor(UiLanguage.SIMPLIFIED_CHINESE).toLanguageTag());
        assertEquals("en", UiLanguage.localeFor(UiLanguage.ENGLISH).toLanguageTag());
    }
}
