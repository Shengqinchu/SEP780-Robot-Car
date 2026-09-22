package io.github.shengqinchu.sep780;

import org.junit.Test;

import java.util.Arrays;

import static org.junit.Assert.assertEquals;

public final class VoiceCommandParserTest {
    @Test
    public void mapsTheFiniteChineseAndEnglishVocabulary() {
        assertEquals(VoiceCommandParser.Action.LINE, VoiceCommandParser.parse("开始循迹"));
        assertEquals(VoiceCommandParser.Action.FORWARD, VoiceCommandParser.parse("前进"));
        assertEquals(VoiceCommandParser.Action.BACKWARD, VoiceCommandParser.parse("go back"));
        assertEquals(VoiceCommandParser.Action.LEFT, VoiceCommandParser.parse("turn left"));
        assertEquals(VoiceCommandParser.Action.RIGHT, VoiceCommandParser.parse("向右转"));
        assertEquals(VoiceCommandParser.Action.UNKNOWN, VoiceCommandParser.parse("随便走走"));
    }

    @Test
    public void stopAlwaysWinsAcrossRecognizerCandidates() {
        assertEquals(VoiceCommandParser.Action.STOP,
                VoiceCommandParser.parseCandidates(Arrays.asList("前进", "停止")));
        assertEquals(VoiceCommandParser.Action.STOP, VoiceCommandParser.parse("不要停止"));
    }
}
