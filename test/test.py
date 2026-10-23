# SPDX-License-Identifier: Apache-2.0
"""Black-box pin regression shared by the official RTL and gate-level jobs.

The RTL harness uses 80MHz; gate-level unit-delay models use a slow clock.
Neither demonstrates pad/board or SDF timing closure.
The separate ddr-regression workflow exhaustively checks sample transport.
"""
import os
import cocotb
from cocotb.triggers import Timer

@cocotb.test()
async def test_project(dut):
    half_period_ns=float(os.environ.get("TEST_CORE_PERIOD_NS", "12.5"))/2
    dut.ena.value=1
    dut.clk.value=0
    dut.rst_n.value=0
    dut.ui_in.value=0
    dut.uio_in.value=31
    part=0
    snapshot=0
    frame_expected=None
    last_kind=None
    frames=0
    invalids=0
    count_checks=0

    async def tick(bus, reset=False, expected=None):
        nonlocal part,snapshot,frame_expected,last_kind,frames,invalids,count_checks
        dut.clk.value=0
        dut.ui_in.value=bus
        dut.rst_n.value=0 if reset else 1
        await Timer(half_period_ns,unit='ns')
        dut.clk.value=1
        await Timer(half_period_ns,unit='ns')
        oe=int(dut.uio_oe.value)
        io=int(dut.uio_out.value)
        word=(io>>5)*256+int(dut.uo_out.value)
        assert oe in (0xe0,0xe1)
        assert io&0x1e==0
        if reset:
            assert oe==0xe0 and word==0 and io&1==0
            part=0;last_kind=None
            return
        if not oe&1:return
        kind=io&1
        if last_kind is not None:assert kind!=last_kind,'TYPE must alternate'
        last_kind=kind
        if not kind:
            if expected is not None:
                assert word==1024,('constant-input COUNT',word)
                count_checks+=1
            return
        tag=word>>9
        payload=word&511
        if tag==3:
            part=0;invalids+=1
            assert expected is None,'fully warmed window is unexpectedly invalid'
            return
        assert tag==part,('fragment order',tag,part)
        if tag==0:
            snapshot=payload;part=1;frame_expected=expected
        elif tag==1:
            snapshot|=payload<<9;part=2
        else:
            snapshot|=payload<<18;part=0;frames+=1
            if frame_expected is not None:
                assert snapshot==frame_expected,('27-bit amplitude',snapshot,frame_expected)

    async def stream(value,n,level=1):
        raw=value^8192 # ADC default two's complement; input normalized once in ASIC
        expected=(abs(value-8192)*32768)>>2
        for i in range(n):
            stable=expected if i>=35000*(1<<(level-1)) else None
            await tick(128|(raw&127),expected=stable)
            await tick(raw>>7,expected=stable)

    for _ in range(5):await tick(0,reset=True)
    for _ in range(5):await tick(0) # illegal LEVEL=31 must not start handoff
    assert int(dut.uio_oe.value)==0xe0
    dut.uio_in.value=0
    for _ in range(5):await tick(0) # LEVEL0 exceeds this interface's word rate
    assert int(dut.uio_oe.value)==0xe0
    dut.uio_in.value=1
    await tick(0) # configuration capture
    await tick(128)
    await tick(64)
    dut.uio_in.value=0 # controller releases TYPE pad long before handoff
    await stream(0,42000) # full-scale sum exercises bit26 of 27-bit output
    assert frames>100
    await stream(8192,36000)
    before=invalids
    await tick(128)
    await tick(128) # duplicate lower: discard pair and clear measurement window
    await tick(0)
    for _ in range(4):
        await tick(128);await tick(64)
    assert invalids>before,'missing tag3 after framing error'
    await stream(0,36000)
    assert count_checks>1000 and frames>1000
    # Interrupt a lower half with global reset; handoff must return to input mode.
    await tick(128)
    for _ in range(4):await tick(0,reset=True)
    dut.uio_in.value=1
    await tick(0)
    await tick(64) # upper without a lower cannot resurrect the interrupted pair
    for _ in range(8):await tick(128);await tick(64)
    assert int(dut.uio_oe.value)==0xe0
    # Reset selects a different LEVEL. The same exact pin-only checks run on
    # both RTL and the physically generated gate-level netlist.
    for _ in range(4):await tick(0,reset=True)
    dut.uio_in.value=2
    await tick(0)
    dut.uio_in.value=31 # subsequent pin changes must not overwrite the latch
    before_frames=frames
    await stream(0,74000,level=2)
    assert frames>before_frames+100,'LEVEL2 did not fill its 16-period window'
    for _ in range(4):await tick(0,reset=True)
    dut.uio_in.value=5
    await tick(0)
    dut.uio_in.value=31
    await stream(0,4096,level=5)
    word=(int(dut.uio_out.value)>>5)*256+int(dut.uo_out.value)
    assert word==255,('LEVEL5 selected-sample COUNT before handoff',word)
    assert int(dut.uio_oe.value)==0xe0
    dut._log.info('PIN_AND_GATE_PASS levels=1,2,5 frames=%d invalids=%d count_checks=%d',frames,invalids,count_checks)
