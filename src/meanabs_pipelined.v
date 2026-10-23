`default_nettype none
// Pipelined, numerically identical version of meanabs_candidate.
//
// meanabs_candidate performs, on the clock edge of the 2048th sample,
//   |x-mid| -> 25-bit block add -> 16:1 history read -> 29-bit add/subtract
// in a single cycle. That chain is the worst register-to-register setup path
// in the 80 MHz build. The 16-period sum only changes once per 2048 samples,
// so the same arithmetic is split over four stages here:
//   A: |x-mid| registered, block position advanced
//   B: block accumulation; block total registered at the period end
//   C: history write, expired block read from a register prepared in advance,
//      difference (new block - expired block) registered
//   D: 29-bit running sum updated with the registered difference
// Every result equals meanabs_candidate's result exactly, three clock cycles
// later. Each stage is reset by the module reset delayed by its stage index,
// so reset behaviour is the original behaviour shifted by the same amount.
module meanabs_pipelined #(parameter integer INPUT_BITS=14)(
 input wire clk, rst_n, sample_valid,
 input wire [INPUT_BITS-1:0] sample,
 output reg [INPUT_BITS+10:0] result_sum,
 output reg result_valid,
 output reg [INPUT_BITS+14:0] result_sum16,
 output reg result16_valid
);
 localparam integer SUMW = INPUT_BITS + 11;   // single-period sum width (25)
 localparam integer S16W = INPUT_BITS + 15;   // 16-period sum width (29)
 localparam [INPUT_BITS-1:0] MIDPOINT = {1'b1,{(INPUT_BITS-1){1'b0}}};

 // Reset delayed per stage (rst_s[0] = rst_n for stage A).
 reg rst_s1, rst_s2, rst_s3;
 always @(posedge clk) begin
   rst_s1 <= rst_n;
   rst_s2 <= rst_s1;
   rst_s3 <= rst_s2;
 end

 // ---------------- stage A ----------------
 reg [10:0] position;
 reg [INPUT_BITS-1:0] mag_a;
 reg valid_a, last_a;
 wire [INPUT_BITS-1:0] magnitude = sample[INPUT_BITS-1] ? sample-MIDPOINT : MIDPOINT-sample;
 always @(posedge clk) begin
   if (!rst_n) begin
     position <= 0; valid_a <= 0; last_a <= 0; mag_a <= 0;
   end else begin
     valid_a <= sample_valid;
     if (sample_valid) begin
       mag_a <= magnitude;
       last_a <= (position == 11'd2047);
       position <= position + 1'b1;
     end
   end
 end

 // ---------------- stage B ----------------
 reg [SUMW-1:0] accumulator;
 reg [SUMW-1:0] block_b;
 reg valid_b;
 wire [SUMW-1:0] updated = accumulator + {{(SUMW-INPUT_BITS){1'b0}}, mag_a};
 always @(posedge clk) begin
   if (!rst_s1) begin
     accumulator <= 0; valid_b <= 0; block_b <= 0;
   end else begin
     valid_b <= 0;
     if (valid_a) begin
       if (last_a) begin
         block_b <= updated; valid_b <= 1; accumulator <= 0;
       end else accumulator <= updated;
     end
   end
 end

 // ---------------- stage C ----------------
 reg [SUMW-1:0] history[0:15];
 reg [3:0] history_pointer;
 reg [4:0] history_count;
 reg [SUMW-1:0] expired_c;          // prepared one cycle ahead of use
 reg signed [SUMW:0] diff_c;        // new block - expired block
 reg valid_c, ready_c;
 always @(posedge clk) begin
   // History only changes at block ends (>= 2048 samples apart), so this
   // registered copy always holds the entry that the next block will expire.
   expired_c <= (history_count == 16) ? history[history_pointer] : {SUMW{1'b0}};
   if (!rst_s2) begin
     history_pointer <= 0; history_count <= 0;
     valid_c <= 0; ready_c <= 0; diff_c <= 0;
     result_sum <= 0; result_valid <= 0;
   end else begin
     valid_c <= 0; result_valid <= 0;
     if (valid_b) begin
       result_sum <= block_b; result_valid <= 1;
       history[history_pointer] <= block_b;
       history_pointer <= history_pointer + 1'b1;
       if (history_count < 16) history_count <= history_count + 1'b1;
       diff_c <= $signed({1'b0, block_b}) - $signed({1'b0, expired_c});
       valid_c <= 1;
       ready_c <= (history_count >= 15);
     end
   end
 end

 // ---------------- stage D ----------------
 reg [S16W-1:0] smooth_accumulator;
 wire [S16W-1:0] smooth_next = smooth_accumulator + {{(S16W-SUMW-1){diff_c[SUMW]}}, diff_c};
 always @(posedge clk) begin
   if (!rst_s3) begin
     smooth_accumulator <= 0; result_sum16 <= 0; result16_valid <= 0;
   end else begin
     result16_valid <= 0;
     if (valid_c) begin
       smooth_accumulator <= smooth_next;
       if (ready_c) begin result_sum16 <= smooth_next; result16_valid <= 1; end
     end
   end
 end
endmodule
`default_nettype wire
