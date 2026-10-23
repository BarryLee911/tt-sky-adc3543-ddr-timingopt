// Experimental 12-bit rectified accumulator with original physical output pins.
// TYPE=0: original 11-bit COUNT; TYPE=1: three tagged 9-bit pieces of a 27-bit sum.
// Original single-word magnitude readers must be updated. Not a tapeout-ready netlist.
`default_nettype none
module tt_um_sine_area_detector_12bit #(
    parameter integer HANDOFF_WAIT_CYCLES = 80000
) (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,

    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    wire _unused = &{ena, 1'b0};

    wire adc_sign;
    assign adc_sign = (ui_in >= 8'h80);

    reg [4:0] config_level;
    reg       config_valid;

    always @* begin
        config_level = uio_in[4:0];
        config_valid     = 1'b0;

        if (uio_in[4:0] <= 5'd23)
            config_valid = 1'b1;
    end

    wire square_wave;
    wire overlap_bit;
    assign overlap_bit = adc_sign == square_wave;

    reg       config_latched_valid;

    reg  [26:0] prescale_count;

    reg [26:0] prescale_terminal_latched;
    wire [26:0] config_terminal;
    assign config_terminal =
        (27'd1 << config_level) - 27'd1;

    reg         take_sample_q;
    wire [26:0] prescale_terminal_m1;
    wire        take_sample_d;
    assign prescale_terminal_m1 = {
        prescale_terminal_latched[26:1] | {26{~prescale_terminal_latched[0]}},
        ~prescale_terminal_latched[0]};

    wire [31:0] count_is_terminal;
    genvar terminal_level;
    generate
        for (terminal_level = 0; terminal_level < 32; terminal_level = terminal_level + 1) begin : g_terminal
            if (terminal_level < 24) begin : g_legal
                assign count_is_terminal[terminal_level] =
                    (prescale_count == ((27'd1 << terminal_level) - 27'd1));
            end else begin : g_illegal
                assign count_is_terminal[terminal_level] = 1'b0;
            end
        end
    endgenerate
    assign take_sample_d =
        !config_latched_valid ?
            (config_valid && count_is_terminal[config_level]) :
        take_sample_q ?
            ~prescale_terminal_latched[0] :
            (prescale_count == prescale_terminal_m1);


    // During configuration uio[4:0] is LEVEL. After it has latched:
    // sample[11:4] = ui_in[7:0], sample[3:0] = uio_in[4:1].
    reg sample_valid;
    reg [11:0] sample_adc;
    reg sample_overlap;
    reg [10:0] sample_position;
    reg stats_reset;
    reg [2047:0] overlap_history;
    reg [10:0] history_pointer;
    reg [11:0] running_sum;
    reg        window_full;

    assign square_wave = history_pointer[10];

    wire        oldest_overlap;
    wire        effective_oldest_overlap;
    wire [11:0] slide_sum_next;

    assign oldest_overlap = overlap_history[2047];

    assign effective_oldest_overlap = window_full ? oldest_overlap : 1'b0;
    assign slide_sum_next =
        ( sample_overlap && !effective_oldest_overlap) ? (running_sum + 12'd1) :
        (!sample_overlap &&  effective_oldest_overlap) ? (running_sum - 12'd1) :
                                            running_sum;


    wire take_sample = take_sample_q;
    wire backend_process;
    wire stats_clearing;
    localparam integer HANDOFF_CYCLES =
        (HANDOFF_WAIT_CYCLES < 1) ? 1 : HANDOFF_WAIT_CYCLES;

    localparam [16:0] HANDOFF_LAST = HANDOFF_CYCLES - 1;
    reg [16:0] handoff_count;
    reg output_ready;

    wire [10:0] area_latest;

    reg [10:0] output_data;
    reg output_kind;
    wire send_peak; // Name retained only for the unchanged alternating TYPE schedule.
    assign area_latest = running_sum[11] ? 11'd2047 : running_sum[10:0];
    assign send_peak = rst_n && output_ready && !output_kind;
    wire frontend_run;
    wire handoff_active;
    wire handoff_due;
    assign frontend_run = (rst_n !== 1'b0);
    assign backend_process = (stats_reset !== 1'b1) && sample_valid;
    assign stats_clearing = (stats_reset === 1'b1);
    assign handoff_active = frontend_run && config_latched_valid && !output_ready;
    assign handoff_due = (handoff_count == HANDOFF_LAST);

    wire history_count_enable;
    wire handoff_count_enable;
    assign history_count_enable =
        ((frontend_run && take_sample) === 1'b1);
    assign handoff_count_enable =
        ((handoff_active && (handoff_due !== 1'b1)) === 1'b1);

    always @(posedge clk) begin
        prescale_count <=
            (rst_n === 1'b0) ? 27'd0 :
            ((frontend_run && config_latched_valid) === 1'b1) ?
                (take_sample_q ? 27'd0 : prescale_count + 27'd1) :
                prescale_count;
        history_pointer <=
            (rst_n === 1'b0) ? 11'd0 :
            history_count_enable ? history_pointer + 11'd1 : history_pointer;
        handoff_count <=
            (rst_n === 1'b0) ? 17'd0 :
            handoff_count_enable ? handoff_count + 17'd1 : handoff_count;
    end


    wire [22:0] amplitude_sum;
    wire [26:0] amplitude_sum16;
    wire amplitude_valid, amplitude16_valid;
    meanabs_candidate #(.INPUT_BITS(12)) amplitude_core (
        .clk(clk), .rst_n(rst_n), .sample_valid(backend_process), .sample(sample_adc),
        .result_sum(amplitude_sum), .result_valid(amplitude_valid),
        .result_sum16(amplitude_sum16), .result16_valid(amplitude16_valid)
    );
    reg [26:0] amplitude_latest;
    reg amplitude_ready;
    reg [26:0] amplitude_snapshot;
    reg [1:0] amplitude_fragment;

    always @(posedge clk) begin
        stats_reset <= !rst_n;
        if (!rst_n) begin
            config_latched_valid <= 1'b0;
            prescale_terminal_latched <= 27'd0;
            take_sample_q <= 1'b0;
            sample_valid <= 1'b0;
            sample_adc <= 12'd2048;
            sample_overlap <= 1'b0;
            sample_position <= 11'd0;
            output_ready <= 1'b0;
            output_data <= 11'd0;
            output_kind <= 1'b0;
            amplitude_latest <= 0;
            amplitude_ready <= 0;
            amplitude_snapshot <= 0;
            amplitude_fragment <= 0;
        end else begin
            if (amplitude16_valid) begin
                amplitude_latest <= amplitude_sum16;
                amplitude_ready <= 1;
            end
        end
        if (frontend_run && !config_latched_valid && config_valid) begin
            prescale_terminal_latched <= config_terminal;
            config_latched_valid <= 1'b1;
        end
        if (frontend_run)
            take_sample_q <= take_sample_d;
        if (frontend_run && take_sample) begin
            sample_adc <= {ui_in,uio_in[4:1]};
            sample_overlap <= overlap_bit;
            sample_position <= history_pointer;
        end
        if (handoff_active && handoff_due)
            output_ready <= 1'b1;
        if (frontend_run) begin
            sample_valid <= take_sample;
            output_kind <= send_peak;
            if (stats_reset) begin
                output_data <= 0;
            end else if (!send_peak) begin
                output_data <= area_latest;
            end else if (!amplitude_ready) begin
                // TYPE=1, tag=3 means the 16-period window is not yet ready.
                output_data <= {2'b11,9'd0};
                amplitude_fragment <= 0;
            end else begin
                // Same 11-bit output pads. TYPE=1 carries tag[1:0]+payload[8:0].
                // Freeze all 27 bits at tag 0; later updates cannot tear the frame.
                case (amplitude_fragment)
                    0: begin
                        amplitude_snapshot <= amplitude_latest;
                        output_data <= {2'b00,amplitude_latest[8:0]};
                        amplitude_fragment <= 1;
                    end
                    1: begin
                        output_data <= {2'b01,amplitude_snapshot[17:9]};
                        amplitude_fragment <= 2;
                    end
                    default: begin
                        output_data <= {2'b10,amplitude_snapshot[26:18]};
                        amplitude_fragment <= 0;
                    end
                endcase
            end
        end
    end
    always @(posedge clk) begin
        running_sum <=
            (stats_reset === 1'b1) ? 12'd0 :
            ((backend_process === 1'b1) ? slide_sum_next : running_sum);
    end


    always @(posedge clk) begin
        if (stats_reset) window_full <= 1'b0;
        if (backend_process) overlap_history <= {overlap_history[2046:0], sample_overlap};
        if (backend_process && (sample_position == 11'd2047)) window_full <= 1'b1;
    end
    assign uo_out = output_data[7:0];
    assign uio_out = {output_data[10:8],4'b0000,output_kind};
    assign uio_oe = output_ready ? 8'he1 : 8'he0;
endmodule
`default_nettype wire
