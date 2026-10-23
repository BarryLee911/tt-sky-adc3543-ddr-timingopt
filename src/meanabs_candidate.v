`default_nettype none
// Experimental amplitude datapath, not yet integrated with the TinyTapeout pin protocol.
// Preserve the full integer sum. Host calibration for an ideal sine:
// amplitude_in_8bit_codes = sum * pi / (2 * 2048 * 2**(INPUT_BITS-8)).
// No pi multiplier or division in this module. Non-sinusoidal waveforms need another calibration.
module meanabs_candidate #(parameter integer INPUT_BITS=14)(
 input wire clk, rst_n, sample_valid,
 input wire [INPUT_BITS-1:0] sample,
 output reg [INPUT_BITS+10:0] result_sum,
 output reg result_valid,
 output reg [INPUT_BITS+14:0] result_sum16,
 output reg result16_valid
);
 localparam [INPUT_BITS-1:0] MIDPOINT = {1'b1,{(INPUT_BITS-1){1'b0}}};
 reg [10:0] position;
 reg [INPUT_BITS+10:0] accumulator;
 wire [INPUT_BITS-1:0] magnitude = sample[INPUT_BITS-1] ? sample-MIDPOINT : MIDPOINT-sample;
 wire [INPUT_BITS+10:0] updated = accumulator + {{11{1'b0}},magnitude};
 reg [INPUT_BITS+10:0] history[0:15];
 reg [3:0] history_pointer;
 reg [4:0] history_count;
 reg [INPUT_BITS+14:0] smooth_accumulator;
 wire [INPUT_BITS+14:0] expired = (history_count==16) ? {4'b0,history[history_pointer]} : 0;
 wire [INPUT_BITS+14:0] smooth_next = smooth_accumulator + {4'b0,updated} - expired;
 always @(posedge clk) begin
   if(!rst_n) begin
     position<=0;accumulator<=0;result_sum<=0;result_valid<=0;
     history_pointer<=0;history_count<=0;smooth_accumulator<=0;result_sum16<=0;result16_valid<=0;
   end else begin
     result_valid<=0;result16_valid<=0;
     if(sample_valid) begin
       position<=position+1'b1;
       if(position==11'd2047) begin
         result_sum<=updated;result_valid<=1;accumulator<=0;
         history[history_pointer]<=updated;history_pointer<=history_pointer+1'b1;
         if(history_count<16) history_count<=history_count+1'b1;
         smooth_accumulator<=smooth_next;
         if(history_count>=15) begin result_sum16<=smooth_next;result16_valid<=1;end
       end else accumulator<=updated;
     end
   end
 end
endmodule
`default_nettype wire
