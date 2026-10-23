`timescale 1ns/1ps
// Line-by-line Verilog transliteration of test/test.py (the official cocotb
// black-box pin test), so it can run without cocotb. Same stimulus, same
// assertions, same tick structure: inputs change with clk low, outputs are
// read half a period after the rising edge.
// Compile with -DUSE_ORIG to run it on the reference build instead.
module tb_official_equiv;
  reg clk = 0, rst_n = 0;
  reg [7:0] ui_in = 0, uio_in = 31;
  wire [7:0] uo_out, uio_out, uio_oe;
`ifdef USE_ORIG
  tt_um_sine_area_detector_adc3542_ddr_orig dut(
`else
  tt_um_sine_area_detector_adc3542_ddr dut(
`endif
    .ui_in(ui_in), .uo_out(uo_out), .uio_in(uio_in), .uio_out(uio_out),
    .uio_oe(uio_oe), .ena(1'b1), .clk(clk), .rst_n(rst_n));

  integer part = 0, snapshot = 0, frame_expected = -1, last_kind = -1;
  integer frames = 0, invalids = 0, count_checks = 0, inv_before, before_frames;
  integer oe, io, word, kind, tag, payload, i;

  task tick(input integer bus, input integer reset, input integer expected);
    begin
      clk = 0; ui_in = bus; rst_n = reset ? 0 : 1;
      #6.25; clk = 1; #6.25;
      oe = uio_oe; io = uio_out; word = (io >> 5) * 256 + uo_out;
      if ((^{uio_oe, uio_out, uo_out}) === 1'bx) $fatal(1, "X on outputs");
      if (!(oe == 8'he0 || oe == 8'he1)) $fatal(1, "oe value %h", oe);
      if ((io & 8'h1e) != 0) $fatal(1, "io bits 4:1");
      if (reset) begin
        if (!(oe == 8'he0 && word == 0 && (io & 1) == 0)) $fatal(1, "reset outputs");
        part = 0; last_kind = -1;
      end else if (oe & 1) begin
        kind = io & 1;
        if (last_kind != -1 && kind == last_kind) $fatal(1, "TYPE must alternate");
        last_kind = kind;
        if (!kind) begin
          if (expected != -1) begin
            if (word != 1024) $fatal(1, "constant-input COUNT %0d", word);
            count_checks = count_checks + 1;
          end
        end else begin
          tag = word >> 9; payload = word & 511;
          if (tag == 3) begin
            part = 0; invalids = invalids + 1;
            if (expected != -1) $fatal(1, "fully warmed window is unexpectedly invalid");
          end else begin
            if (tag != part) $fatal(1, "fragment order tag=%0d part=%0d", tag, part);
            if (tag == 0) begin snapshot = payload; part = 1; frame_expected = expected; end
            else if (tag == 1) begin snapshot = snapshot | (payload << 9); part = 2; end
            else begin
              snapshot = snapshot | (payload << 18); part = 0; frames = frames + 1;
              if (frame_expected != -1 && snapshot != frame_expected)
                $fatal(1, "27-bit amplitude %0d expected %0d", snapshot, frame_expected);
            end
          end
        end
      end
    end
  endtask

  task stream(input integer value, input integer n, input integer level);
    integer raw, expected, stable, k;
    begin
      raw = value ^ 8192;
      expected = ((value > 8192 ? value - 8192 : 8192 - value) * 32768) >> 2;
      for (k = 0; k < n; k = k + 1) begin
        stable = (k >= 35000 * (1 << (level - 1))) ? expected : -1;
        tick(128 | (raw & 127), 0, stable);
        tick(raw >> 7, 0, stable);
      end
    end
  endtask

  initial begin
    for (i = 0; i < 5; i = i + 1) tick(0, 1, -1);
    for (i = 0; i < 5; i = i + 1) tick(0, 0, -1);
    if (uio_oe != 8'he0) $fatal(1, "illegal LEVEL31 started handoff");
    uio_in = 0;
    for (i = 0; i < 5; i = i + 1) tick(0, 0, -1);
    if (uio_oe != 8'he0) $fatal(1, "LEVEL0 started handoff");
    uio_in = 1;
    tick(0, 0, -1); tick(128, 0, -1); tick(64, 0, -1);
    uio_in = 0;
    stream(0, 42000, 1);
    if (!(frames > 100)) $fatal(1, "frames after first stream");
    stream(8192, 36000, 1);
    inv_before = invalids;
    tick(128, 0, -1); tick(128, 0, -1); tick(0, 0, -1);
    for (i = 0; i < 4; i = i + 1) begin tick(128, 0, -1); tick(64, 0, -1); end
    if (!(invalids > inv_before)) $fatal(1, "missing tag3 after framing error");
    stream(0, 36000, 1);
    if (!(count_checks > 1000 && frames > 1000)) $fatal(1, "coverage");
    tick(128, 0, -1);
    for (i = 0; i < 4; i = i + 1) tick(0, 1, -1);
    uio_in = 1;
    tick(0, 0, -1); tick(64, 0, -1);
    for (i = 0; i < 8; i = i + 1) begin tick(128, 0, -1); tick(64, 0, -1); end
    if (uio_oe != 8'he0) $fatal(1, "handoff after interrupted reset");
    for (i = 0; i < 4; i = i + 1) tick(0, 1, -1);
    uio_in = 2;
    tick(0, 0, -1);
    uio_in = 31;
    before_frames = frames;
    stream(0, 74000, 2);
    if (!(frames > before_frames + 100)) $fatal(1, "LEVEL2 did not fill its 16-period window");
    for (i = 0; i < 4; i = i + 1) tick(0, 1, -1);
    uio_in = 5;
    tick(0, 0, -1);
    uio_in = 31;
    stream(0, 4096, 5);
    word = (uio_out >> 5) * 256 + uo_out;
    if (word != 255) $fatal(1, "LEVEL5 selected-sample COUNT inv_before handoff %0d", word);
    if (uio_oe != 8'he0) $fatal(1, "LEVEL5 oe");
    $display("OFFICIAL_PIN_TEST_PASS,frames=%0d,invalids=%0d,count_checks=%0d", frames, invalids, count_checks);
    $finish;
  end
endmodule
