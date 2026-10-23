`timescale 1ns/1ps
// Cycle-exact pin equivalence between the reference build and the
// timing-optimized build. After every clock edge:
//   * the testbenches change inputs while clk is low, so the rst_n value seen
//     just after an edge is the value that edge used. Whenever that value is
//     low, the optimized outputs must already be in their reset state;
//   * if rst_n was low on any of the last SKIP edges no comparison is made
//     (the reference still shows pre-reset values for D cycles);
//   * otherwise every optimized pin must equal the reference pin from exactly
//     D clock edges earlier (4-state comparison, X must match X).
module pin_equiv #(parameter integer D = 5) (
    input wire clk, rst_n,
    input wire [7:0] ref_uo, ref_uio, ref_oe,
    input wire [7:0] opt_uo, opt_uio, opt_oe
);
    localparam integer SKIP = D + 2;
    reg [23:0] hist [0:D-1];
    reg [SKIP-1:0] rst_hist = {SKIP{1'b0}};
    reg seen_reset = 1'b0;
    integer compared = 0, skipped = 0, reset_checks = 0, k;
    always @(posedge clk) begin
        #0.003;
        if (rst_n === 1'b0) begin
            if (opt_oe !== 8'he0 || opt_uo !== 8'h00 || opt_uio !== 8'h00)
                $fatal(1, "pin_equiv: optimized outputs not cleared by reset at %0t", $time);
            reset_checks = reset_checks + 1;
        end
        if (seen_reset && (&rst_hist) && (rst_n === 1'b1)) begin
            if ({opt_uo, opt_uio, opt_oe} !== hist[D-1])
                $fatal(1, "pin_equiv: mismatch at %0t opt uo=%h uio=%h oe=%h ref(-%0d) uo=%h uio=%h oe=%h",
                       $time, opt_uo, opt_uio, opt_oe, D, hist[D-1][23:16], hist[D-1][15:8], hist[D-1][7:0]);
            compared = compared + 1;
        end else skipped = skipped + 1;
        for (k = D-1; k > 0; k = k - 1) hist[k] = hist[k-1];
        hist[0] = {ref_uo, ref_uio, ref_oe};
        rst_hist = {rst_hist[SKIP-2:0], (rst_n === 1'b1)};
        if (rst_n === 1'b0) seen_reset = 1'b1;
    end
endmodule
