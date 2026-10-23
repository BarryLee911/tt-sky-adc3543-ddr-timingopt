# ADC3543 interface and timing assumptions

Source: [TI ADC354x datasheet SBAS840C](https://www.ti.com/lit/ds/symlink/adc3542.pdf),
pin table p4, timing p13, Figure 7-2 p26, default table at left of Figure 8-44
p49, mode initialization p51, register 0x07 p57, and power-up sequence p73.
The remapped example at the right of Figure 8-44 is not the selected mapping.

| ADC pin | ASIC pin | DCLK high | Following DCLK low |
|---|---|---|---|
| D17 (18) | ui[0] | bit0 | bit7 |
| D16 (19) | ui[1] | bit1 | bit8 |
| D15 (20) | ui[2] | bit2 | bit9 |
| D14 (21) | ui[3] | bit3 | bit10 |
| D13 (22) | ui[4] | bit4 | bit11 |
| D12 (23) | ui[5] | bit5 | bit12 |
| D11 (24) | ui[6] | bit6 | bit13 |
| DCLK (26) | ui[7] | 1 | 0 |

After supplies/reference and ADC sampling clock settle, follow the hardware
reset and approximately 200000-clock calibration sequence in the datasheet.
At 40MHz, 200000 ADC clocks are approximately 5ms; preserve the required analog
settling/startup waits as well. SPI SCLK is limited to 20MHz, not the 80MHz core.
Program 0x07=0xA9 first, then 0x13=1, wait approximately 1ms, and 0x13=0.
The e-fuse load resets other SPI writes, so configure other features afterward.
Use the default raw, two's-complement, 14-bit mapping without DDC. This matches
the RTL default INPUT_TWOS_COMPLEMENT=1. For ADC offset binary, configure its
digital/format registers as documented and set that RTL parameter to zero;
do not convert twice. Verify constant and ramp test codes before measurement.

The source data and DCLK change near the same edges. Family tPD from sample-clock
falling edge to DCLK rising edge is 3/5/7ns minimum/typical/maximum. At 25MSPS,
tCD lists -0.4ns minimum and -0.2ns nominal; its MAX column is blank. The nominal
number is not a guaranteed maximum. The falling edge and actual load/duty/skew
budget need separate confirmation. Level-converter data rate is not a timing
closure result. Seven data signals and DCLK require a coherent capture aperture;
independent bit synchronizers cannot fix an uncontrolled bus crossing.

Define H=12.5ns and capture phase PHI after the ideal half-word launch.
With earliest/latest arrivals Amin/Amax, a valid aperture must satisfy both:

```
Amax + setup + uncertainty < PHI
PHI < H + Amin - hold - uncertainty
```

The 2025-case sweep retains the original absolute-ns assumptions: tPD=3/5/7ns,
data-to-DCLK skew +/-1ns, falling-edge shift +/-2ns, model setup=1ns, hold=0.5ns,
and uncertainty=0.5ns. These are illustrative bounds, not the measured board or
ASIC specifications, and were not scaled down to fit the new period.

Direct connection requires the strict interval 11.5 < PHI < 11.5ns: its width
is zero. PHI=11.5ns can pass a nonnegative guard comparison at a boundary, but
has zero remaining guard margin and is not a robust sampling phase. Adding the
illustrative 3..5ns common translation delay requires 16.5 < PHI < 14.5ns: its
width is -2ns and no tested phase satisfies all scenarios. Correct decoded data
inside a forbidden setup/hold guard does not establish correct capture.

The analysis script exits successfully when it reproduces this expected result;
timing_validation.json explicitly reports NO_POSITIVE_COMMON_MARGIN_UNDER_PREVIOUS_ASSUMPTIONS.
This is evidence that the retained envelope does not close at 80MHz; it is not
evidence that the ADC3543 cannot convert at 40MS/s. Obtain actual min/max delays
and duty/skew/CTS limits and a shared clock phase before claiming board operation.

The files in constraints/ are an interface-fragment and an explicitly illustrative
budget. They are not automatically loaded into the official GDS build: physical
defaults and board-specific DDR signoff are distinct evidence. Never false-path
the eight ui inputs or declare DCLK an unrelated clock to make violations vanish.
constraints/clock_profile_80mhz.tcl sets only H=12.5ns and deliberately supplies
no invented phase or arrival bounds. illustrative_model_budget.tcl is retained
as a historical 40.96MHz example and must not be sourced for this 80MHz profile.
The SDC fragment supports only H/2 < PHI < H; another phase convention requires
consistent virtual launch-edge changes, not an out-of-range phase value.
Real signoff requires cell libraries, pad/slew limits, clocks after CTS, board
and translator min/max PVT delays, ADC output duty bounds and setup AND hold.

If an upper half is captured on edge C, sample_valid is registered after C;
the decimator considers it at C+1. Only every D=2^(LEVEL-1)th complete word
advances COUNT and accumulation. Since reset/reacquisition, raw zero-based
indices D-1, 2D-1, 3D-1, ... are selected. LEVEL1 selects all complete words.
A completed 16-period result reaches
the latest register at C+2 and can enter a new tag0 snapshot at C+3 or later.
Selected-sample index n starts from the first selected word; its COUNT reference is
floor((n mod 2048)/1024). ADC conversion latency and release phase still require
calibration against the physical excitation reference. Equal clock frequencies
alone do not establish absolute phase or error-free 80MHz operation.

Changing LEVEL does not slow the physical DDR receiver or the ADC clock. The
ADC must still emit one half-word per clk; slowing DCLK without changing the
receiver architecture is a framing error, even at a higher LEVEL. Input timing
budgets above therefore apply to every mode. Effective rates, first-result
latency, reference frequency, reset-only reconfiguration and aliasing limits
are documented in [multi-level behavior](multilevel.md).
