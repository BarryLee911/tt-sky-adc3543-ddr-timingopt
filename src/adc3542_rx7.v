`default_nettype none
// Single clk domain. clk MUST sample the stable centre of every DDR half-word.
// TI SBAS840C Fig 7-2, DEFAULT 14-bit mapper: DCLK=1 -> bits[6:0],
// then DCLK=0 -> bits[13:7]. Pins: D17..D11 -> half_data[0]..[6].
// This is a mesochronous, phase-constrained interface, NOT an async CDC.
module adc3542_rx7 #(
    parameter integer INPUT_TWOS_COMPLEMENT = 1
) (
    input wire clk, rst_n,
    input wire [6:0] half_data,
    input wire dclk_level,
    output reg [13:0] sample14,
    output reg sample_valid,
    output reg framing_error,
    output reg locked
);
    reg [6:0] lower;
    reg have_lower, seen, last_level;
    wire [13:0] assembled = {half_data, lower};
    always @(posedge clk) begin
        if (!rst_n) begin
            lower <= 0; have_lower <= 0; seen <= 0; last_level <= 0;
            sample14 <= 14'd8192; sample_valid <= 0;
            framing_error <= 0; locked <= 0;
        end else begin
            sample_valid <= 0;
            framing_error <= 0;
            seen <= 1;
            last_level <= dclk_level;
            if (seen && (dclk_level == last_level)) begin
                // Repeated marker: missing/repeated half, stopped clock, or bad phase.
                // Do not reuse either half. The next complete 1->0 pair reacquires.
                have_lower <= 0;
                framing_error <= 1;
                locked <= 0;
            end else if (dclk_level) begin
                lower <= half_data;
                have_lower <= 1;
            end else if (have_lower) begin
                sample14 <= assembled ^ (INPUT_TWOS_COMPLEMENT ? 14'h2000 : 14'h0000);
                sample_valid <= 1;
                have_lower <= 0;
                locked <= 1;
            end
        end
    end
endmodule
`default_nettype wire
