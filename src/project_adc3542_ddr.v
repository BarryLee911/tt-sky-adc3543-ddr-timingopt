// Timing-optimized version of the ADC3543 / 80 MHz / 7+7 DDR core.
// Derived from the preserved project_12bit.v lineage. LEVEL=1..23.
// Existing output pads, alternating TYPE, 80000-clock handoff, 3x9-bit frames.
//
// Three changes relative to the reference build (test/reference/project_adc3542_ddr_orig.v):
//   1. Reset path: rst_n and all other inputs are registered once before use, and
//      the measurement reset is registered before it fans out. No input pin
//      drives the large reset trees combinationally any more.
//   2. backend_process (22-bit compare + gating) is registered before it drives
//      the 2048-bit COUNT history enable; the selected sample is registered with it.
//   3. The 16-period amplitude sum uses meanabs_pipelined instead of the
//      single-cycle meanabs_candidate (identical integers, 3 cycles later).
// Output-side signals are delayed so that all of them see the same total
// latency. After reset release the pins equal the reference pins delayed by
// exactly OUT_LATENCY (=5) clock cycles. Asserting rst_n still clears the
// outputs on the next clock edge, as before.
`default_nettype none
module tt_um_sine_area_detector_adc3542_ddr #(
    parameter integer HANDOFF_WAIT_CYCLES = 80000,
    parameter integer INPUT_TWOS_COMPLEMENT = 1
) (
    input wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input wire [7:0] uio_in,
    output wire [7:0] uio_out, uio_oe,
    input wire ena, clk, rst_n
);
    wire _unused = &{ena,uio_in_q[7:5],1'b0};

    // ---------------- (1) registered inputs ----------------
    reg [7:0] ui_in_q, uio_in_q;
    reg rst_q;
    always @(posedge clk) begin
        ui_in_q  <= ui_in;
        uio_in_q <= uio_in;
        rst_q    <= rst_n;
    end

    reg config_latched_valid;
    reg [4:0] config_level_latched;
    reg [21:0] decimation_terminal;
    always @(posedge clk) begin
        if (!rst_q) begin
            config_latched_valid <= 0;
            config_level_latched <= 0;
            decimation_terminal <= 0;
        end else if (!config_latched_valid &&
                     uio_in_q[4:0] >= 5'd1 && uio_in_q[4:0] <= 5'd23) begin
            config_latched_valid <= 1;
            config_level_latched <= uio_in_q[4:0];
            // One complete word every two clk edges. Select each 2^(LEVEL-1)th
            // complete word; never prescale the half-word receiver itself.
            decimation_terminal <= (22'd1 << (uio_in_q[4:0] - 5'd1)) - 22'd1;
        end
    end
    // LEVEL=0 cannot deliver a complete 14-bit word per clk on this interface.
    wire receiver_rst_n = rst_q && config_latched_valid;
    wire [13:0] sample14;
    wire sample_valid, rx_error, rx_locked;
    adc3542_rx7 #(.INPUT_TWOS_COMPLEMENT(INPUT_TWOS_COMPLEMENT)) receiver (
        .clk(clk), .rst_n(receiver_rst_n), .half_data(ui_in_q[6:0]),
        .dclk_level(ui_in_q[7]), .sample14(sample14), .sample_valid(sample_valid),
        .framing_error(rx_error), .locked(rx_locked)
    );
    // An error clears both measurement windows. Receiver stays active to
    // reacquire. No stale window survives a detected discontinuity.
    wire measurement_rst_n = receiver_rst_n && !rx_error;
    reg [21:0] decimation_count;
    wire complete_sample = sample_valid && measurement_rst_n && rx_locked;
    wire backend_select = complete_sample && (decimation_count == decimation_terminal);
    always @(posedge clk) begin
        if (!measurement_rst_n) decimation_count <= 0;
        else if (complete_sample) begin
            if (backend_select) decimation_count <= 0;
            else decimation_count <= decimation_count + 22'd1;
        end
    end

    // ---------------- (1)+(2) registered measurement reset and strobe ----------------
    // A complete word needs two half-words, so sample14 is stable for at least
    // two clocks; the registered copy below is taken in the same cycle as the
    // strobe and is therefore exactly the word the reference design processes.
    reg measurement_rst_q;      // drives the COUNT registers and amplitude stage A
    reg backend_process;        // registered strobe (same name as reference for tests)
    reg [13:0] sample_q;
    always @(posedge clk) begin
        measurement_rst_q <= measurement_rst_n;
        backend_process   <= backend_select;
        sample_q          <= sample14;
    end

    reg [2047:0] overlap_history;
    reg [10:0] history_pointer;
    reg [11:0] running_sum;
    reg window_full;
    wire sample_overlap = (sample_q[13] == history_pointer[10]);
    wire effective_oldest_overlap = window_full ? overlap_history[2047] : 1'b0;
    wire [11:0] slide_sum_next =
        (sample_overlap && !effective_oldest_overlap) ? running_sum + 12'd1 :
        (!sample_overlap && effective_oldest_overlap) ? running_sum - 12'd1 : running_sum;
    always @(posedge clk) begin
        if (!measurement_rst_q) begin
            history_pointer <= 0; running_sum <= 0; window_full <= 0;
        end else if (backend_process) begin
            history_pointer <= history_pointer + 11'd1;
            running_sum <= slide_sum_next;
            if (history_pointer == 11'd2047) window_full <= 1;
        end
    end
    // Match the prototype's unreset shift history. window_full masks old entries.
    always @(posedge clk) begin
        if (backend_process) overlap_history <= {overlap_history[2046:0], sample_overlap};
    end

    // ---------------- (3) pipelined amplitude accumulation ----------------
    wire [24:0] amplitude_sum;
    wire [28:0] amplitude_sum16;
    wire amplitude_valid, amplitude16_valid;
    meanabs_pipelined #(.INPUT_BITS(14)) amplitude_core (
        .clk(clk), .rst_n(measurement_rst_q), .sample_valid(backend_process), .sample(sample_q),
        .result_sum(amplitude_sum), .result_valid(amplitude_valid),
        .result_sum16(amplitude_sum16), .result16_valid(amplitude16_valid)
    );

    // ---------------- latency alignment for the output block ----------------
    // Relative to the reference design: inputs +1, COUNT state +2,
    // 16-period sum +5. Delay the remaining output-block inputs to +5.
    localparam integer OUT_LATENCY = 5;
    reg [10:0] area_d1, area_d2, area_d3;
    reg [3:0] rst_line, cfg_line, meas_line;
    wire [10:0] area_now = running_sum[11] ? 11'd2047 : running_sum[10:0];
    always @(posedge clk) begin
        area_d1 <= area_now; area_d2 <= area_d1; area_d3 <= area_d2;
        rst_line  <= {rst_line[2:0],  rst_q};
        cfg_line  <= {cfg_line[2:0],  config_latched_valid};
        meas_line <= {meas_line[2:0], measurement_rst_n};
    end
    wire [10:0] area_latest = area_d3;            // reference area_latest, 5 cycles late
    wire rst_out   = rst_line[3];                 // reference rst_n, 5 cycles late
    wire cfg_out   = cfg_line[3];
    wire meas_out  = meas_line[3];
    // Output registers also clear immediately when the reset pin is asserted.
    wire out_rst_n = rst_n && rst_out;

    localparam integer HANDOFF_CYCLES = (HANDOFF_WAIT_CYCLES < 1) ? 1 : HANDOFF_WAIT_CYCLES;
    localparam [16:0] HANDOFF_LAST = HANDOFF_CYCLES - 1;
    reg [16:0] handoff_count;
    reg output_ready;
    reg [10:0] output_data;
    reg output_kind;
    wire handoff_active = out_rst_n && cfg_out && !output_ready;
    wire send_peak = out_rst_n && output_ready && !output_kind;
    reg [26:0] amplitude_latest, amplitude_snapshot;
    reg amplitude_ready;
    reg [1:0] amplitude_fragment;
    always @(posedge clk) begin
        if (!out_rst_n) begin
            handoff_count <= 0; output_ready <= 0;
            output_data <= 0; output_kind <= 0;
        end else begin
            if (handoff_active) begin
                if (handoff_count == HANDOFF_LAST) output_ready <= 1;
                else handoff_count <= handoff_count + 17'd1;
            end
            output_kind <= send_peak;
            if (!send_peak) output_data <= meas_out ? area_latest : 11'd0;
            else if (!meas_out || !amplitude_ready)
                output_data <= {2'b11,9'd0};
            else case (amplitude_fragment)
                0: begin
                    amplitude_snapshot <= amplitude_latest;
                    output_data <= {2'b00,amplitude_latest[8:0]};
                end
                1: output_data <= {2'b01,amplitude_snapshot[17:9]};
                default: output_data <= {2'b10,amplitude_snapshot[26:18]};
            endcase
        end
        if (!meas_out) begin
            amplitude_latest <= 0; amplitude_snapshot <= 0;
            amplitude_ready <= 0; amplitude_fragment <= 0;
        end else begin
            if (amplitude16_valid) begin
                // Scale once, AFTER the full 29-bit 16-period integer accumulation.
                amplitude_latest <= amplitude_sum16[28:2];
                amplitude_ready <= 1;
            end
            if (send_peak) begin
                if (!amplitude_ready || amplitude_fragment == 2) amplitude_fragment <= 0;
                else amplitude_fragment <= amplitude_fragment + 1'b1;
            end
        end
    end
    assign uo_out = output_data[7:0];
    assign uio_out = {output_data[10:8],4'b0000,output_kind};
    assign uio_oe = output_ready ? 8'he1 : 8'he0;
endmodule
`default_nettype wire
