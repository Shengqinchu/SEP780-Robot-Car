#include "unity.h"
#include "controller.h"
#include "protocol.h"
#include "ir_input.h"
#include "fnk0041_io.h"
#include "Arduino.h"
#include <stdio.h>
#include <string.h>
#include <inttypes.h>

using namespace robot;
Controller car;
Inputs sample;

Config baseline() {
  Config cfg;
  cfg.cruise_pwm=90; cfg.turn_reduction_pwm=50; cfg.max_pwm=150;
  cfg.left_trim_pwm=cfg.right_trim_pwm=0;
  cfg.obstacle_stop_mm=200; cfg.obstacle_resume_mm=300;
  cfg.clear_hold_ms=600; cfg.range_max_age_ms=250; cfg.input_max_age_ms=100;
  cfg.line_lost_ms=400; cfg.manual_lease_ms=350; cfg.serial_lease_ms=1200;
  cfg.battery_min_mv=6600; cfg.battery_max_mv=9000;
  return cfg;
}

Inputs fresh(uint32_t now = 1000, uint8_t line = 2, uint16_t mm = 800) {
  Inputs in;
  in.sampled_ms = in.range_ms = now;
  in.line = line; in.range_mm = mm; in.battery_mv = 7400;
  in.sample_valid = in.range_valid = in.head_ready = true;
  return in;
}
void setUp() { car = Controller(baseline()); sample = fresh(); fake::reset(); }
void tearDown() {}
void lineArm(Source source = Source::Infrared, uint32_t now = 1000) {
  sample = fresh(now); TEST_ASSERT_TRUE(car.arm(Mode::Line, source, sample, now));
}
void manualArm(Source source = Source::Infrared, uint32_t now = 1000) {
  sample = fresh(now); TEST_ASSERT_TRUE(car.arm(Mode::Manual, source, sample, now));
}
void stopped(State state) {
  TEST_ASSERT_FALSE(car.armed()); TEST_ASSERT_EQUAL_INT(state, car.state());
  TEST_ASSERT_EQUAL_INT(0, car.output().left); TEST_ASSERT_EQUAL_INT(0, car.output().right);
}
ParseResult parseText(CommandParser& parser, const char* text, Command& command, uint32_t now = 1000) {
  ParseResult result = ParseResult::None;
  for (; *text; ++text) { const ParseResult current = parser.feed(*text, now, command); if (current != ParseResult::None) result = current; }
  return result;
}

void boot_stops() { car.tick(sample, 1000); stopped(State::Idle); }
void default_config_valid() { TEST_ASSERT_TRUE(Config().valid()); }
void invalid_config_cannot_arm() { Config cfg=baseline(); cfg.cruise_pwm = 200; car = Controller(cfg); TEST_ASSERT_FALSE(car.arm(Mode::Line, Source::Serial, sample, 1000)); stopped(State::BadConfig); }
void inverted_threshold_rejected() { Config cfg; cfg.obstacle_resume_mm = cfg.obstacle_stop_mm; TEST_ASSERT_FALSE(cfg.valid()); }
void bad_timing_rejected() { Config cfg; cfg.manual_lease_ms = 0; TEST_ASSERT_FALSE(cfg.valid()); }
void boot_inputs_not_ready() { Inputs in; TEST_ASSERT_FALSE(car.arm(Mode::Line, Source::Serial, in, 1000)); stopped(State::SensorFault); }
void head_must_settle() { sample.head_ready = false; TEST_ASSERT_FALSE(car.arm(Mode::Line, Source::Serial, sample, 1000)); stopped(State::SensorFault); }
void blocked_arm_rejected() { sample.range_mm = 299; TEST_ASSERT_FALSE(car.arm(Mode::Manual, Source::Serial, sample, 1000)); stopped(State::Obstacle); }
void invalid_mode_rejected() { TEST_ASSERT_FALSE(car.arm(Mode::Idle, Source::Serial, sample, 1000)); stopped(State::Idle); }
void arm_requires_line() { sample.line = 0; TEST_ASSERT_FALSE(car.arm(Mode::Line, Source::Serial, sample, 1000)); stopped(State::LineLost); }
void mode_owner_not_stolen() { lineArm(); TEST_ASSERT_FALSE(car.arm(Mode::Manual, Source::Serial, sample, 1000)); TEST_ASSERT_EQUAL_INT(Source::Infrared, car.owner()); }
void center_drives_straight() { lineArm(); Drive d = car.tick(sample, 1000); TEST_ASSERT_EQUAL_INT(90, d.left); TEST_ASSERT_EQUAL_INT(90, d.right); }
void all_five_track_patterns() {
  const uint8_t patterns[] = {1,2,3,4,6}; const int left[] = {90,90,90,0,40}; const int right[] = {0,90,40,90,90};
  lineArm();
  for (unsigned i=0; i<5; ++i) { sample = fresh(1010+i*10, patterns[i]); Drive d = car.tick(sample, sample.sampled_ms); TEST_ASSERT_EQUAL_INT(left[i], d.left); TEST_ASSERT_EQUAL_INT(right[i], d.right); }
}
void lost_line_immediate_zero() { lineArm(); sample = fresh(1010,0); Drive d=car.tick(sample,1010); TEST_ASSERT_EQUAL_INT(0,d.left); TEST_ASSERT_TRUE(car.armed()); }
void brief_loss_recovers() { lineArm(); car.tick(fresh(1010,0),1010); Drive d=car.tick(fresh(1200,2),1200); TEST_ASSERT_EQUAL_INT(90,d.left); }
void sustained_loss_latches() { lineArm(); car.tick(fresh(1010,0),1010); car.tick(fresh(1410,0),1410); stopped(State::LineLost); car.tick(fresh(1500),1500); stopped(State::LineLost); }
void split_line_latches() { lineArm(); car.tick(fresh(1010,5),1010); stopped(State::AmbiguousLine); }
void crossing_latches() { lineArm(); car.tick(fresh(1010,7),1010); stopped(State::AmbiguousLine); }
void obstacle_stops_at_boundary() { lineArm(); Drive d=car.tick(fresh(1010,2,200),1010); TEST_ASSERT_EQUAL_INT(0,d.left); TEST_ASSERT_EQUAL_INT(State::Obstacle,car.state()); TEST_ASSERT_TRUE(car.armed()); }
void obstacle_hysteresis_holds() { lineArm(); car.tick(fresh(1010,2,190),1010); car.tick(fresh(1100,2,250),1100); TEST_ASSERT_EQUAL_INT(State::ClearWait,car.state()); TEST_ASSERT_EQUAL_INT(0,car.output().left); }
void obstacle_recovers_after_sustained_clear() { lineArm(); car.tick(fresh(1010,2,190),1010); for (uint32_t t=1100;t<=1700;t+=100) car.tick(fresh(t,2,400),t); TEST_ASSERT_EQUAL_INT(State::Following,car.state()); TEST_ASSERT_EQUAL_INT(90,car.output().left); }
void one_clear_sample_never_resumes() { lineArm(); car.tick(fresh(1010,2,190),1010); Inputs in=fresh(1100,2,400); car.tick(in,1100); in.sampled_ms=1700; car.tick(in,1700); stopped(State::SensorFault); }
void renewed_obstacle_resets_clear_timer() { lineArm(); car.tick(fresh(1010,2,190),1010); car.tick(fresh(1100,2,400),1100); car.tick(fresh(1300,2,400),1300); car.tick(fresh(1400,2,250),1400); car.tick(fresh(1500,2,400),1500); car.tick(fresh(1700,2,400),1700); TEST_ASSERT_EQUAL_INT(0,car.output().left); }
void lost_during_obstacle_latches() { lineArm(); car.tick(fresh(1010,0,190),1010); car.tick(fresh(1410,0,190),1410); stopped(State::LineLost); }
void no_echo_is_fault_not_clear() { lineArm(); sample.range_valid=false; car.tick(sample,1000); stopped(State::SensorFault); }
void stale_range_is_fault() { lineArm(); sample.sampled_ms=1250; car.tick(sample,1250); stopped(State::SensorFault); }
void stale_whole_input_is_fault() { lineArm(); car.tick(sample,1100); stopped(State::SensorFault); }
void low_voltage_stops() { lineArm(); sample.battery_mv=6599; car.tick(sample,1000); stopped(State::LowBattery); }
void excessive_voltage_stops() { lineArm(); sample.battery_mv=10000; car.tick(sample,1000); stopped(State::SensorFault); }
void malformed_sensor_bits_stop() { lineArm(); sample.line=8; car.tick(sample,1000); stopped(State::SensorFault); }
void impossible_range_stops() { lineArm(); sample.range_mm=19; car.tick(sample,1000); stopped(State::SensorFault); }
void fault_requires_explicit_rearm() { lineArm(); sample.range_valid=false; car.tick(sample,1000); car.tick(fresh(1100),1100); stopped(State::SensorFault); TEST_ASSERT_TRUE(car.arm(Mode::Line,Source::Infrared,fresh(1200),1200)); }
void stop_is_latched() { lineArm(); car.stop(); car.tick(fresh(1100),1100); stopped(State::Stopped); }
void serial_line_times_out() { lineArm(Source::Serial); car.tick(fresh(2200),2200); stopped(State::RemoteTimeout); }
void serial_ping_keeps_line_alive() { lineArm(Source::Serial); TEST_ASSERT_TRUE(car.ping(Source::Serial,2000)); car.tick(fresh(2500),2500); TEST_ASSERT_TRUE(car.armed()); }
void late_ping_does_not_revive() { lineArm(Source::Serial); TEST_ASSERT_FALSE(car.ping(Source::Serial,2200)); stopped(State::RemoteTimeout); }
void wrong_owner_ping_ignored() { lineArm(Source::Serial); TEST_ASSERT_FALSE(car.ping(Source::Infrared,2000)); car.tick(fresh(2200),2200); stopped(State::RemoteTimeout); }
void infrared_line_is_standalone() { lineArm(); car.tick(fresh(100000),100000); TEST_ASSERT_TRUE(car.armed()); }
void manual_starts_with_zero() { manualArm(); Drive d=car.tick(sample,1000); TEST_ASSERT_EQUAL_INT(0,d.left); }
void manual_drive_and_reverse() { manualArm(); TEST_ASSERT_TRUE(car.drive(-80,70,Source::Infrared,1010)); Drive d=car.tick(fresh(1010),1010); TEST_ASSERT_EQUAL_INT(-80,d.left); TEST_ASSERT_EQUAL_INT(70,d.right); }
void manual_lease_expires() { manualArm(); car.drive(90,90,Source::Infrared,1010); car.tick(fresh(1360),1360); stopped(State::RemoteTimeout); }
void ping_does_not_extend_movement() { manualArm(Source::Serial); car.drive(90,90,Source::Serial,1010); car.ping(Source::Serial,1300); car.tick(fresh(1360),1360); stopped(State::RemoteTimeout); }
void late_drive_does_not_revive() { manualArm(); TEST_ASSERT_FALSE(car.drive(90,90,Source::Infrared,1350)); stopped(State::RemoteTimeout); }
void wrong_owner_drive_ignored() { manualArm(); TEST_ASSERT_FALSE(car.drive(90,90,Source::Serial,1010)); TEST_ASSERT_EQUAL_INT(0,car.output().left); }
void out_of_range_drive_stops() { manualArm(); TEST_ASSERT_FALSE(car.drive(151,90,Source::Infrared,1010)); stopped(State::CommandError); }
void manual_obstacle_does_not_auto_resume() { manualArm(); car.drive(90,90,Source::Infrared,1010); car.tick(fresh(1020,2,190),1020); stopped(State::Obstacle); car.tick(fresh(1100),1100); stopped(State::Obstacle); }
void trim_never_creates_motion_from_zero() { Config cfg=baseline(); cfg.left_trim_pwm=20; car=Controller(cfg); lineArm(); Drive d=car.tick(fresh(1010,4),1010); TEST_ASSERT_EQUAL_INT(0,d.left); }
void trim_clamps_to_ceiling() { Config cfg=baseline(); cfg.left_trim_pwm=40; car=Controller(cfg); manualArm(); car.drive(140,-150,Source::Infrared,1010); Drive d=car.tick(fresh(1010),1010); TEST_ASSERT_EQUAL_INT(150,d.left); TEST_ASSERT_EQUAL_INT(-150,d.right); }
void uptime_rollover_lease() { manualArm(Source::Serial,0xFFFFFF00UL); car.drive(80,80,Source::Serial,0xFFFFFF10UL); car.tick(fresh(0x00000060UL),0x60); TEST_ASSERT_TRUE(car.armed()); car.tick(fresh(0x70),0x70); stopped(State::RemoteTimeout); }
void uptime_rollover_clear() { lineArm(Source::Infrared,0xFFFFFF00UL); car.tick(fresh(0xFFFFFF10UL,2,100),0xFFFFFF10UL); uint32_t t=0xFFFFFF20UL; for (unsigned n=0;n<=6;++n,t+=100) car.tick(fresh(t,2,400),t); TEST_ASSERT_EQUAL_INT(State::Following,car.state()); }

void protocol_valid_commands() {
  const char* lines[]={"S 1 STOP\n","S 2 ARM LINE\r\n","S 3 ARM MANUAL\n","S 4 DRIVE -90 80\n","S 5 PING\n","S 6 STATUS\n"};
  const CommandType types[]={CommandType::Stop,CommandType::ArmLine,CommandType::ArmManual,CommandType::Drive,CommandType::Ping,CommandType::Status};
  CommandParser p; Command c;
  for(unsigned n=0;n<6;++n){ TEST_ASSERT_EQUAL_INT(ParseResult::Ready,parseText(p,lines[n],c)); TEST_ASSERT_EQUAL_INT(types[n],c.type); TEST_ASSERT_EQUAL_INT(n+1,c.sequence); }
}
void protocol_bad_numbers_and_tokens() {
  const char* lines[]={"S 0 STOP\n","S 65536 STOP\n","S 1 DRIVE 9999999999999999 0\n","S 1 DRIVE 1.5 3\n","S 1 DRIVE +2 3\n","S 1 DRIVE --2 3\n","S 1 ARM LINE extra\n","S 1 arm LINE\n","S 1 STOP x\n","S 1 DRIVE 181 0\n","S 1 DRIVE -181 0\n","S 1 DRIVE - 0\n"};
  for(const char* line:lines){ CommandParser p; Command c; TEST_ASSERT_EQUAL_INT(ParseResult::Invalid,parseText(p,line,c)); }
}
void protocol_split_frame() { CommandParser p; Command c; TEST_ASSERT_EQUAL_INT(ParseResult::None,parseText(p,"S 22 AR",c)); TEST_ASSERT_EQUAL_INT(ParseResult::Ready,parseText(p,"M LINE\n",c,1050)); TEST_ASSERT_EQUAL_INT(22,c.sequence); }
void protocol_overflow_discards_whole_line() { CommandParser p; Command c; for(unsigned n=0;n<64;++n) p.feed('X',1000,c); TEST_ASSERT_EQUAL_INT(ParseResult::None,parseText(p,"S 3 ARM LINE\n",c)); TEST_ASSERT_EQUAL_INT(ParseResult::Ready,parseText(p,"S 4 STOP\n",c)); }
void protocol_timeout_discards_tail() { CommandParser p; Command c; parseText(p,"S 2 ARM ",c); TEST_ASSERT_TRUE(p.expire(1200)); TEST_ASSERT_EQUAL_INT(ParseResult::None,parseText(p,"LINE\n",c,1201)); TEST_ASSERT_EQUAL_INT(ParseResult::Ready,parseText(p,"S 3 STOP\n",c,1202)); }
void protocol_timeout_in_feed_reported() { CommandParser p; Command c; parseText(p,"S ",c); TEST_ASSERT_EQUAL_INT(ParseResult::Invalid,p.feed('1',1200,c)); }
void protocol_embedded_nul_rejected() { CommandParser p; Command c; parseText(p,"S 2 ARM",c); TEST_ASSERT_EQUAL_INT(ParseResult::Invalid,p.feed('\0',1000,c)); TEST_ASSERT_EQUAL_INT(ParseResult::None,parseText(p," LINE\n",c)); }
void protocol_midline_cr_rejected() { CommandParser p; Command c; TEST_ASSERT_EQUAL_INT(ParseResult::Invalid,parseText(p,"S 1\r STOP\n",c)); }
void protocol_blank_line_ignored() { CommandParser p; Command c; TEST_ASSERT_EQUAL_INT(ParseResult::None,parseText(p,"\n",c)); TEST_ASSERT_EQUAL_INT(ParseResult::None,parseText(p,"\r\n",c)); }
void protocol_stop_from_any_owner() { lineArm(); Command c; c.type=CommandType::Stop; TEST_ASSERT_TRUE(execute(car,c,Source::Serial,sample,1000)); stopped(State::Stopped); }
void protocol_status_does_not_renew_lease() { lineArm(Source::Serial); Command c; c.type=CommandType::Status; execute(car,c,Source::Serial,fresh(2100),2100); car.tick(fresh(2200),2200); stopped(State::RemoteTimeout); }

void ir_mapping_and_repeats() { IrInput ir; Command c; TEST_ASSERT_TRUE(ir.decode(0xFF02FD,1000,90,c)); TEST_ASSERT_EQUAL_INT(90,c.left); TEST_ASSERT_TRUE(ir.decode(0xFFFFFFFF,1100,90,c)); TEST_ASSERT_EQUAL_INT(CommandType::Drive,c.type); }
void ir_arm_is_not_repeated() { IrInput ir; Command c; TEST_ASSERT_TRUE(ir.decode(0xFF30CF,1000,90,c)); TEST_ASSERT_EQUAL_INT(CommandType::ArmLine,c.type); TEST_ASSERT_FALSE(ir.decode(0xFFFFFFFF,1100,90,c)); }
void ir_orphan_repeat_ignored() { IrInput ir; Command c; TEST_ASSERT_FALSE(ir.decode(0xFFFFFFFF,1000,90,c)); }
void ir_stale_repeat_ignored() { IrInput ir; Command c; ir.decode(0xFF02FD,1000,90,c); TEST_ASSERT_FALSE(ir.decode(0xFFFFFFFF,1181,90,c)); }
void ir_unknown_code_ignored() { IrInput ir; Command c; TEST_ASSERT_FALSE(ir.decode(0x123456,1000,90,c)); }
void ir_stop_mapping() { const uint32_t codes[]={0xFFA25D,0xFF6897,0xFFA857,0xFFB04F}; IrInput ir; Command c; for(uint32_t code:codes){ TEST_ASSERT_TRUE(ir.decode(code,1000,90,c)); TEST_ASSERT_EQUAL_INT(CommandType::Stop,c.type); } }
void ir_directions_mapping() { const uint32_t codes[]={0xFF02FD,0xFF9867,0xFFE01F,0xFF906F}; const int l[]={90,-90,-90,90},r[]={90,-90,90,-90}; IrInput ir; Command c; for(unsigned n=0;n<4;++n){ TEST_ASSERT_TRUE(ir.decode(codes[n],1000,90,c)); TEST_ASSERT_EQUAL_INT(l[n],c.left); TEST_ASSERT_EQUAL_INT(r[n],c.right); } }

void io_boot_stops_motors_centers_head() { Fnk0041Io io; fake::pwm[5]=fake::pwm[6]=99; io.begin(); TEST_ASSERT_EQUAL_INT(0,fake::pwm[5]); TEST_ASSERT_EQUAL_INT(0,fake::pwm[6]); TEST_ASSERT_EQUAL_INT(hardware::servo_center_degrees,fake::angle); TEST_ASSERT_EQUAL_INT(2,fake::servo_pin); TEST_ASSERT_EQUAL_INT(INPUT,fake::modes[A0]); }
void io_does_not_range_before_settle() { Fnk0041Io io; io.begin(); fake::now=hardware::servo_settle_ms-1; Inputs in=io.read(); TEST_ASSERT_FALSE(in.head_ready); TEST_ASSERT_FALSE(in.range_valid); }
void io_maps_tracking_and_battery() { Fnk0041Io io; io.begin(); fake::digital[A1]=1; fake::digital[A2]=0; fake::digital[A3]=1; Inputs in=io.read(); TEST_ASSERT_EQUAL_INT(hardware::black_reads_high?5:2,in.line); TEST_ASSERT_EQUAL_INT(380UL*hardware::adc_full_scale_mv/1023UL,in.battery_mv); }
void io_sonar_converts_without_8bit_truncation() { Fnk0041Io io; io.begin(); fake::now=500; fake::pulse=5800; Inputs in=io.read(); TEST_ASSERT_TRUE(in.range_valid); TEST_ASSERT_EQUAL_INT(1000,in.range_mm); TEST_ASSERT_EQUAL_UINT32(25000,fake::timeout); }
void io_no_echo_invalidates_previous_reading() { Fnk0041Io io; io.begin(); fake::now=500; fake::pulse=5800; io.read(); fake::pulse=0; fake::now=600; Inputs in=io.read(); TEST_ASSERT_FALSE(in.range_valid); TEST_ASSERT_EQUAL_INT(0,in.range_mm); }
void io_forward_pin_polarity() { Fnk0041Io io; io.begin(); Drive d; d.left=80; d.right=90; io.write(d); TEST_ASSERT_EQUAL_INT(hardware::invert_left_motor?HIGH:LOW,fake::digital[4]); TEST_ASSERT_EQUAL_INT(hardware::invert_right_motor?LOW:HIGH,fake::digital[3]); TEST_ASSERT_EQUAL_INT(80,fake::pwm[6]); TEST_ASSERT_EQUAL_INT(90,fake::pwm[5]); }
void io_reverse_inserts_zero_cycle() { Fnk0041Io io; io.begin(); Drive d; d.left=d.right=90; io.write(d); d.left=d.right=-90; io.write(d); TEST_ASSERT_EQUAL_INT(0,fake::pwm[6]); io.write(d); TEST_ASSERT_EQUAL_INT(90,fake::pwm[6]); TEST_ASSERT_EQUAL_INT(hardware::invert_left_motor?LOW:HIGH,fake::digital[4]); TEST_ASSERT_EQUAL_INT(hardware::invert_right_motor?HIGH:LOW,fake::digital[3]); }
void bounded_random_inputs_preserve_stop_and_pwm_limits() {
  uint32_t rng=1234567;
  for(uint32_t n=0;n<10000;++n){ rng=rng*1664525UL+1013904223UL; uint32_t now=1000+n*10; Inputs in=fresh(now,static_cast<uint8_t>((rng>>8)&7),static_cast<uint16_t>(100+(rng%1000))); if((rng&31)==0) in.range_valid=false;
    if(!car.armed()&&(rng&3)==0) car.arm(Mode::Line,Source::Infrared,in,now);
    Drive d=car.tick(in,now); TEST_ASSERT_TRUE(d.left>=0 && d.left<=150 && d.right>=0 && d.right<=150);
    if(!car.armed()||!in.range_valid||in.range_mm<=200||in.line==0||in.line==5||in.line==7){ TEST_ASSERT_EQUAL_INT(0,d.left); TEST_ASSERT_EQUAL_INT(0,d.right); }
  }
}

int replay() {
  Controller controller;
  uint32_t now;
  unsigned line, mm, valid, mv, action;
  int left, right;
  puts("ms,mode,state,left_pwm,right_pwm,accepted");
  while (scanf("%" SCNu32 " %u %u %u %u %u %d %d", &now,&line,&mm,&valid,&mv,&action,&left,&right)==8) {
    if(line>7||mm>4000||valid>1||mv>20000||action>5||left < -180||left>180||right < -180||right>180) return 2;
    Inputs in=fresh(now,static_cast<uint8_t>(line),static_cast<uint16_t>(mm)); in.range_valid=valid!=0; in.battery_mv=static_cast<uint16_t>(mv);
    controller.tick(in,now);
    Command c;
    bool accepted=true;
    switch(action){ case 1:c.type=CommandType::ArmLine;break; case 2:c.type=CommandType::ArmManual;break; case 3:c.type=CommandType::Drive;c.left=static_cast<int16_t>(left);c.right=static_cast<int16_t>(right);break;case 4:c.type=CommandType::Ping;break;case 5:c.type=CommandType::Stop;break;default:break; }
    if(action) accepted=execute(controller,c,Source::Serial,in,now);
    Drive d=controller.tick(in,now);
    printf("%" PRIu32 ",%u,%u,%d,%d,%u\n",now,static_cast<unsigned>(controller.mode()),static_cast<unsigned>(controller.state()),d.left,d.right,accepted?1:0);
  }
  return feof(stdin)?0:2;
}

int main(int argc,char** argv) {
  if(argc==2&&strcmp(argv[1],"--replay")==0) return replay();
  UNITY_BEGIN();
  RUN_TEST(boot_stops); RUN_TEST(default_config_valid); RUN_TEST(invalid_config_cannot_arm); RUN_TEST(inverted_threshold_rejected); RUN_TEST(bad_timing_rejected);
  RUN_TEST(boot_inputs_not_ready); RUN_TEST(head_must_settle); RUN_TEST(blocked_arm_rejected); RUN_TEST(invalid_mode_rejected); RUN_TEST(arm_requires_line); RUN_TEST(mode_owner_not_stolen);
  RUN_TEST(center_drives_straight); RUN_TEST(all_five_track_patterns); RUN_TEST(lost_line_immediate_zero); RUN_TEST(brief_loss_recovers); RUN_TEST(sustained_loss_latches); RUN_TEST(split_line_latches); RUN_TEST(crossing_latches);
  RUN_TEST(obstacle_stops_at_boundary); RUN_TEST(obstacle_hysteresis_holds); RUN_TEST(obstacle_recovers_after_sustained_clear); RUN_TEST(one_clear_sample_never_resumes); RUN_TEST(renewed_obstacle_resets_clear_timer); RUN_TEST(lost_during_obstacle_latches);
  RUN_TEST(no_echo_is_fault_not_clear); RUN_TEST(stale_range_is_fault); RUN_TEST(stale_whole_input_is_fault); RUN_TEST(low_voltage_stops); RUN_TEST(excessive_voltage_stops); RUN_TEST(malformed_sensor_bits_stop); RUN_TEST(impossible_range_stops); RUN_TEST(fault_requires_explicit_rearm); RUN_TEST(stop_is_latched);
  RUN_TEST(serial_line_times_out); RUN_TEST(serial_ping_keeps_line_alive); RUN_TEST(late_ping_does_not_revive); RUN_TEST(wrong_owner_ping_ignored); RUN_TEST(infrared_line_is_standalone);
  RUN_TEST(manual_starts_with_zero); RUN_TEST(manual_drive_and_reverse); RUN_TEST(manual_lease_expires); RUN_TEST(ping_does_not_extend_movement); RUN_TEST(late_drive_does_not_revive); RUN_TEST(wrong_owner_drive_ignored); RUN_TEST(out_of_range_drive_stops); RUN_TEST(manual_obstacle_does_not_auto_resume);
  RUN_TEST(trim_never_creates_motion_from_zero); RUN_TEST(trim_clamps_to_ceiling); RUN_TEST(uptime_rollover_lease); RUN_TEST(uptime_rollover_clear);
  RUN_TEST(protocol_valid_commands); RUN_TEST(protocol_bad_numbers_and_tokens); RUN_TEST(protocol_split_frame); RUN_TEST(protocol_overflow_discards_whole_line); RUN_TEST(protocol_timeout_discards_tail); RUN_TEST(protocol_timeout_in_feed_reported); RUN_TEST(protocol_embedded_nul_rejected); RUN_TEST(protocol_midline_cr_rejected); RUN_TEST(protocol_blank_line_ignored); RUN_TEST(protocol_stop_from_any_owner); RUN_TEST(protocol_status_does_not_renew_lease);
  RUN_TEST(ir_mapping_and_repeats); RUN_TEST(ir_arm_is_not_repeated); RUN_TEST(ir_orphan_repeat_ignored); RUN_TEST(ir_stale_repeat_ignored); RUN_TEST(ir_unknown_code_ignored); RUN_TEST(ir_stop_mapping); RUN_TEST(ir_directions_mapping);
  RUN_TEST(io_boot_stops_motors_centers_head); RUN_TEST(io_does_not_range_before_settle); RUN_TEST(io_maps_tracking_and_battery); RUN_TEST(io_sonar_converts_without_8bit_truncation); RUN_TEST(io_no_echo_invalidates_previous_reading); RUN_TEST(io_forward_pin_polarity); RUN_TEST(io_reverse_inserts_zero_cycle);
  RUN_TEST(bounded_random_inputs_preserve_stop_and_pwm_limits);
  return UNITY_END();
}
