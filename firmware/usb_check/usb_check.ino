// Project-authored USB-only bring-up check. Use a bare, USB-powered Uno.
// No motor, servo, sensor or radio pins are configured.
#include <Arduino.h>

unsigned long lastHeartbeat = 0;
bool ledOn = false;

void setup() {
  pinMode(LED_BUILTIN, OUTPUT);
  digitalWrite(LED_BUILTIN, LOW);
  Serial.begin(115200);
  Serial.println(F("SEP780 USB CHECK READY"));
  Serial.println(F("Send ? to query board status. Actuators are not controlled."));
}

void loop() {
  const unsigned long now = millis();
  if (now - lastHeartbeat >= 1000UL) {
    lastHeartbeat = now;
    ledOn = !ledOn;
    digitalWrite(LED_BUILTIN, ledOn ? HIGH : LOW);
    Serial.print(F("HEARTBEAT ms="));
    Serial.println(now);
  }

  if (Serial.available() > 0) {
    const int command = Serial.read();
    if (command == '?') {
      Serial.println(F("OK board=arduino:avr:uno mode=USB_CHECK actuators=UNCONTROLLED"));
    }
  }
}
