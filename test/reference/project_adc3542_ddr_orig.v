// Derived from the preserved project_12bit.v. LEVEL=1..23.
// Existing output pads, alternating TYPE, 80000-clock handoff, 3x9-bit frames.
`default_nettype none
module tt_um_sine_area_detector_adc3542_ddr_orig #(
    parameter integer HANDOFF_WAIT_CYCLES = 80000,
    parameter integer INPUT_TWOS_COMPLEMENT = 1
) (
    input wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input wire [7:0] uio_in,
    output wire [7:0] uio_out, uio_oe,
    input wire ena, clk, rst_n
);
    wire _unused = &{ena,uio_in[7:5],1'b0};
    reg config_latched_valid;
    reg [4:0] config_level_latched;
    reg [21:0] decimation_terminal;
    always @(posedge clk) begin
        if (!rst_n) begin
            config_latched_valid <= 0;
            config_level_latched <= 0;
            decimation_terminal <= 0;
        end else if (!config_latched_valid &&
                     uio_in[4:0] >= 5'd1 && uio_in[4:0] <= 5'd23) begin
            config_latched_valid <= 1;
            config_level_latched <= uio_in[4:0];
            // One complete word every two clk edges. Select each 2^(LEVEL-1)th
            // complete word; never prescale the half-word receiver itself.
            decimation_terminal <= (22'd1 << (uio_in[4:0] - 5'd1)) - 22'd1;
        end
    end
    // LEVEL=0 cannot deliver a complete 14-bit word per clk on this interface.
    wire receiver_rst_n = rst_n && config_latched_valid;
    wire [13:0] sample14;
    wire sample_valid, rx_error, rx_locked;
    adc3542_rx7 #(.INPUT_TWOS_COMPLEMENT(INPUT_TWOS_COMPLEMENT)) receiver (
        .clk(clk), .rst_n(receiver_rst_n), .half_data(ui_in[6:0]),
        .dclk_level(ui_in[7]), .sample14(sample14), .sample_valid(sample_valid),
        .framing_error(rx_error), .locked(rx_locked)
    );
    // An error clears both measurement windows at the next clk edge. Receiver
    // stays active to reacquire. No stale window survives a detected discontinuity.
    wire measurement_rst_n = receiver_rst_n && !rx_error;
    reg [21:0] decimation_count;
    wire complete_sample = sample_valid && measurement_rst_n && rx_locked;
    wire backend_process = complete_sample && (decimation_count == decimation_terminal);
    always @(posedge clk) begin
        if (!measurement_rst_n) decimation_count <= 0;
        else if (complete_sample) begin
            if (backend_process) decimation_count <= 0;
            else decimation_count <= decimation_count + 22'd1;
        end
    end
    reg [2047:0] overlap_history;
    reg [10:0] history_pointer;
    reg [11:0] running_sum;
    reg window_full;
    wire sample_overlap = (sample14[13] == history_pointer[10]);
    wire effective_oldest_overlap = window_full ? overlap_history[2047] : 1'b0;
    wire [11:0] slide_sum_next =
        (sample_overlap && !effective_oldest_overlap) ? running_sum + 12'd1 :
        (!sample_overlap && effective_oldest_overlap) ? running_sum - 12'd1 : running_sum;
    wire [10:0] area_latest = running_sum[11] ? 11'd2047 : running_sum[10:0];
    always @(posedge clk) begin
        if (!measurement_rst_n) begin
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
    wire [24:0] amplitude_sum;
    wire [28:0] amplitude_sum16;
    wire amplitude_valid, amplitude16_valid;
    meanabs_candidate #(.INPUT_BITS(14)) amplitude_core (
        .clk(clk), .rst_n(measurement_rst_n), .sample_valid(backend_process), .sample(sample14),
        .result_sum(amplitude_sum), .result_valid(amplitude_valid),
        .result_sum16(amplitude_sum16), .result16_valid(amplitude16_valid)
    );
    localparam integer HANDOFF_CYCLES = (HANDOFF_WAIT_CYCLES < 1) ? 1 : HANDOFF_WAIT_CYCLES;
    localparam [16:0] HANDOFF_LAST = HANDOFF_CYCLES - 1;
    reg [16:0] handoff_count;
    reg output_ready;
    reg [10:0] output_data;
    reg output_kind;
    wire handoff_active = rst_n && config_latched_valid && !output_ready;
    wire send_peak = rst_n && output_ready && !output_kind;
    reg [26:0] amplitude_latest, amplitude_snapshot;
    reg amplitude_ready;
    reg [1:0] amplitude_fragment;
    always @(posedge clk) begin
        if (!rst_n) begin
            handoff_count <= 0; output_ready <= 0;
            output_data <= 0; output_kind <= 0;
        end else begin
            if (handoff_active) begin
                if (handoff_count == HANDOFF_LAST) output_ready <= 1;
                else handoff_count <= handoff_count + 17'd1;
            end
            output_kind <= send_peak;
            if (!send_peak) output_data <= measurement_rst_n ? area_latest : 11'd0;
            else if (!measurement_rst_n || !amplitude_ready)
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
        if (!measurement_rst_n) begin
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
