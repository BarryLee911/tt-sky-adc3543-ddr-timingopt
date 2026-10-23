# ADC3543 at 80MHz / 40MS/s

The selected device is ADC3543, with an 80MHz ASIC core and 40MS/s native 7+7
DDR input. This replaces the historical ADC3542 40.96MHz/20.48MS/s working point.
[TI's product page](https://www.ti.com/product/ADC3543) specifies a 65MS/s maximum
for ADC3543. The family SBAS840C datasheet uses an adc3542.pdf URL but covers
ADC3543 as well. A device speed rating is not board timing closure.

The production RTL from the completed multi-level version is unchanged. Existing
module/file/repository names containing adc3542 are retained for compatibility.
The configuration and tests target 80MHz; historic sources and results remain
available in their original local folders and Git commits.

| Quantity | Current target |
|---|---:|
| Core clk / period | 80MHz / 12.5ns |
| ADC sampling / DCLK | 40MS/s / 40MHz |
| Half-word interval / rate per lane | 12.5ns / 80Mbit/s |
| LEVEL1, 2048 selected samples | 19.53125kHz reference, 51.2us period |
| LEVEL1, 16-period window | 0.8192ms |
| TYPE pad direction handoff | 80000 clk = 1ms |
| Three-fragment amplitude frame | 6 clk = 75ns |

The controller must cope with the 80MHz TYPE/data cadence. Repeated frames hold
the latest result and are not independent measurement blocks. Preserve invalid
tag3 semantics and discard unfinished snapshots after a framing error.

LEVEL1..23 and invalid LEVEL0/24..31 rules are retained. Effective sample rate
is 80e6/2^LEVEL; COUNT, rectification and period position advance only for selected
complete samples. See [mode table](multilevel.md). Every mode keeps the physical
ADC and receiver at full rate. Point decimation adds no anti-alias filter.

Keep 2048 samples per reference period: LEVEL1 excitation is 19.53125kHz. Exact
10kHz would require 4000 samples per period and different COUNT/window logic;
that is outside this minimal retarget. Excitation and input conversion latency
still need physical phase calibration. No complete AFE/PCB redesign is included.

SPI initialization must follow the ADC3543 family datasheet. SPI SCLK stays at
or below 20MHz. Approximately 200000 ADC clocks correspond to 5ms at 40MHz;
that calculation does not replace the full power/reference/startup sequence.

## Timing evidence and its limits

The retained delay model has NO positive common capture margin at 80MHz.
Direct: strict 11.5 < PHI < 11.5ns, width 0ns. Illustrative translation:
16.5 < PHI < 14.5ns, width -2ns. The single direct grid point at 11.5ns is a
zero-margin boundary, not a usable capture window. The 2025-case model is rerun
without reducing any absolute-ns delay, skew, duty or guard assumption.

These are assumed envelopes, not measured joint ADC3543/translator/PCB/ASIC
corners. Obtain the actual bounds before deciding the shared clock phase. A
forwarded-DCLK-based architecture, if eventually necessary, requires its own
clock/pad/CTS assessment. This version makes no unverified capture-structure
change, false-path, asynchronous clock-group or multicycle exception.

The official physical flow is retargeted with clock_hz=80000000 and
CLOCK_PERIOD=12.5ns, retaining ordinary single-cycle checks. Its default TT I/O
assumptions remain distinct from the external DDR aperture. Inspect this exact
revision's setup AND hold, RC/PVT, max-slew and max-cap reports; prior 40.96MHz
results cannot establish 80MHz operation. No board or manufactured-chip result
is claimed by a successful GDS job.

The dedicated functional benches use an 80MHz clock. The official cocotb harness
uses 80MHz for RTL, and a deliberately slow 1MHz clock for unit-delay gate models.
The latter verifies generated-netlist functionality and is not high-speed SDF
signoff. The phase-analysis script reproduces and reports the unclosed aperture;
its successful execution is not a timing-pass claim.

Full-rate transport, all 23 real divider intervals, representative complete
windows, independent integer COUNT/sum/snapshot references, resets and detectable
framing errors are rerun for this version. Old synthetic codes test arithmetic;
playing them faster does not create a new physiological/noise/ENOB experiment.
Historical docs/local-validation-summary.json describes only the earlier local
LEVEL1 evidence, not this revision. Current evidence is emitted into build/reports
and the revision's GitHub Actions artifacts.
