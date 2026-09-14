#include "controller.h"
#include "protocol.h"
#include "ir_input.h"
#include "fnk0041_io.h"
#include <IRremote.h>

robot::Controller car;
robot::CommandParser parser;
robot::IrInput remote;
robot::Fnk0041Io board;
IRrecv receiver(9);
decode_results irResult;
uint32_t reportedMs = 0;

void report(const robot::Inputs& in) {
  Serial.print(F("SEP780 v=1 ms=")); Serial.print(millis());
  Serial.print(F(" mode=")); Serial.print(static_cast<uint8_t>(car.mode()));
  Serial.print(F(" state=")); Serial.print(static_cast<uint8_t>(car.state()));
  Serial.print(F(" owner=")); Serial.print(static_cast<uint8_t>(car.owner()));
  Serial.print(F(" line=")); Serial.print(in.line);
  Serial.print(F(" mm=")); Serial.print(in.range_valid ? in.range_mm : 0);
  Serial.print(F(" mv=")); Serial.print(in.battery_mv);
  Serial.print(F(" l=")); Serial.print(car.output().left);
  Serial.print(F(" r=")); Serial.println(car.output().right);
}

void setup() {
  board.begin(); // Motors stop; the ultrasonic head moves to its configured center.
  Serial.begin(115200);
  receiver.enableIRIn();
  Serial.println(F("SEP780 ROBOT READY v=1"));
}

void loop() {
  const robot::Inputs in = board.read();
  uint32_t now = millis();
  board.write(car.tick(in, now));
  if (parser.expire(now)) { car.stop(robot::State::CommandError); board.write(car.output()); }

  robot::Command command;
  for (uint8_t count = 0; count < 32 && Serial.available(); ++count) {
    const robot::ParseResult result = parser.feed(static_cast<char>(Serial.read()), millis(), command);
    if (result == robot::ParseResult::Invalid) {
      car.stop(robot::State::CommandError);
      board.write(car.output());
      Serial.println(F("ERR 0 FRAME"));
    } else if (result == robot::ParseResult::Ready) {
      const bool ok = robot::execute(car, command, robot::Source::Serial, in, millis());
      board.write(car.tick(in, millis()));
      Serial.print(ok ? F("ACK ") : F("ERR ")); Serial.println(command.sequence);
      if (command.type == robot::CommandType::Status) report(in);
    }
  }
  if (receiver.decode(&irResult)) {
    if (irResult.decode_type == NEC && remote.decode(irResult.value, millis(), car.config().cruise_pwm, command)) {
      robot::execute(car, command, robot::Source::Infrared, in, millis());
      board.write(car.tick(in, millis()));
    }
    receiver.resume();
  }
  now = millis();
  if (now - reportedMs >= 200) { reportedMs = now; report(in); }
}
