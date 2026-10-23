# Behavioural demonstration ONLY, not SN74AXC8T245 or ASIC timing specifications.
# These values reproduce the translated model envelope in timing_sweep.py.
set DDR_HALF_PERIOD_NS 24.4140625
set DDR_RX_PHASE_NS 20.0
# tPD 3..7 + common added delay 3..5 + skew +/-1 + duty shift +/-2
set DDR_ARRIVAL_MIN_NS 3.0
set DDR_ARRIVAL_MAX_NS 15.0
set DDR_CLOCK_UNCERTAINTY_NS 0.5
set DDR_INPUT_TRANSITION_NS 1.0
# Cell setup/hold still come from the actual library. Test model assumes 1/.5ns.
