# Approved ADC3543 raw-DDR working point. This is NOT a complete signoff SDC.
set DDR_HALF_PERIOD_NS 12.5
# Intentionally no guessed phase/arrival values: the old illustrative envelope
# has no positive common aperture at 80MHz. Supply actual corner budgets for:
# DDR_RX_PHASE_NS, DDR_ARRIVAL_MIN_NS, DDR_ARRIVAL_MAX_NS,
# DDR_CLOCK_UNCERTAINTY_NS, DDR_INPUT_TRANSITION_NS.
# Then source the existing constraints_adc3542_ddr.sdc interface fragment.
# Preserve ordinary single-cycle timing on every input and internal path.
# Project metadata clock_hz must be 80000000; core clock period must be 12.5ns.
