`default_nettype none
module tt_um_barrylee911_adc3542_ddr (
    input wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input wire [7:0] uio_in,
    output wire [7:0] uio_out, uio_oe,
    input wire ena, clk, rst_n
);
    tt_um_sine_area_detector_adc3542_ddr core (
        .ui_in(ui_in),.uo_out(uo_out),.uio_in(uio_in),
        .uio_out(uio_out),.uio_oe(uio_oe),.ena(ena),.clk(clk),.rst_n(rst_n)
    );
endmodule
`default_nettype wire
