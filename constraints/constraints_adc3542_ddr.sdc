# Interface fragment ONLY. Units: ns. All values must come from the real board
# and ASIC corner budget. Do not source illustrative_model_budget.tcl at signoff.
# Core clk samples at phase PHI after an ideal ADC half-word launch reference.
# This fragment currently requires H/2 < PHI < H, so all waveform edges are within H.
# Other project constraints MUST cover reset/configuration, output delays/loads,
# clock transition, propagated CTS clocks, all PVT corners and reset release.
foreach required {DDR_HALF_PERIOD_NS DDR_RX_PHASE_NS DDR_ARRIVAL_MIN_NS DDR_ARRIVAL_MAX_NS DDR_CLOCK_UNCERTAINTY_NS DDR_INPUT_TRANSITION_NS} {
    if {![info exists $required]} { error "Missing measured/budgeted variable: $required" }
}
set H $DDR_HALF_PERIOD_NS
set PHI $DDR_RX_PHASE_NS
if {$PHI <= $H/2.0 || $PHI >= $H} { error "Choose H/2 < PHI < H for this waveform convention" }
if {$DDR_ARRIVAL_MIN_NS > $DDR_ARRIVAL_MAX_NS} {error "Invalid input delay envelope"}
create_clock -name core_clk -period $H -waveform [list 0 [expr {$H/2.0}]] [get_ports clk]
# Last virtual launch is -PHI relative to core rising edge at zero.
set launch_phase [expr {$H-$PHI}]
create_clock -name adc_half_launch -period $H -waveform [list $launch_phase [expr {$launch_phase+$H/2.0}]]
set_clock_uncertainty $DDR_CLOCK_UNCERTAINTY_NS [get_clocks {core_clk adc_half_launch}]
set_input_delay -clock adc_half_launch -min $DDR_ARRIVAL_MIN_NS [get_ports {ui_in[*]}]
set_input_delay -clock adc_half_launch -max $DDR_ARRIVAL_MAX_NS [get_ports {ui_in[*]}]
set_input_transition $DDR_INPUT_TRANSITION_NS [get_ports {ui_in[*]}]
# ui_in[7] is sampled DATA, not a clock port. No false paths, async clock groups,
# independent per-bit synchronizers, or multicycle exceptions on this bus.
# Keep input captures close/matched and report both setup AND hold to all rx flops.
