`timescale 1ns/1ps
// Real full-rate DDR, no force/deposit and no shortened divider parameter.
// For every LEVEL, run through the first TWO actual terminal counts. At LEVEL23
// this is 8,388,608 complete ADC words, not a hierarchical near-terminal preload.
module tb_levels;
 reg clk=0,rst_n=0;
 reg [7:0] ui=0,uio=31;
 wire [7:0] outp,iop,oep;
 integer level,stride,n,selected,checks=0,total_words=0,previous_select;
 tt_um_sine_area_detector_adc3542_ddr_orig #(.HANDOFF_WAIT_CYCLES(8)) dut(ui,outp,uio,iop,oep,1'b1,clk,rst_n);
 wire [7:0] opt_out,opt_io,opt_oe;
 tt_um_sine_area_detector_adc3542_ddr #(.HANDOFF_WAIT_CYCLES(8)) opt(ui,opt_out,uio,opt_io,opt_oe,1'b1,clk,rst_n);
 pin_equiv #(.D(5)) equiv(.clk(clk),.rst_n(rst_n),.ref_uo(outp),.ref_uio(iop),.ref_oe(oep),.opt_uo(opt_out),.opt_uio(opt_io),.opt_oe(opt_oe));
 task tick(input integer bus,valid,process_sample,resetting);
 begin
   clk=0;ui=bus;rst_n=!resetting;#6.25;
   if(!resetting && dut.backend_process!==process_sample[0])
     $fatal(1,"Selection cadence level=%0d raw_word=%0d",level,n);
   if(resetting)selected=0;
   else if(process_sample)selected=selected+1;
   clk=1;#6.25;
   if(dut.sample_valid!==valid[0] || dut.rx_error!==0)
     $fatal(1,"DDR receiver must run at every LEVEL level=%0d raw_word=%0d",level,n);
   if(valid && dut.sample14!==14'd0)$fatal(1,"Full-word recovery level=%0d",level);
   if(dut.history_pointer!==selected[10:0] || dut.running_sum!==selected[11:0] ||
      dut.amplitude_core.position!==selected[10:0] || dut.amplitude_core.accumulator!==(selected*8192))
     $fatal(1,"Unselected sample advanced COUNT or amplitude level=%0d raw_word=%0d",level,n);
   checks=checks+1;
 end endtask
 initial begin
   for(level=1;level<=23;level=level+1)begin
     uio=31;repeat(3)tick(0,0,0,1);
     uio=level;tick(0,0,0,0);
     stride=1<<(level-1);previous_select=0;
     for(n=0;n<2*stride;n=n+1)begin
       // Offset-binary zero is raw two's-complement 0x2000.
       tick(128,0,previous_select,0);
       tick(64,1,0,0);
       previous_select=((n+1)%stride)==0;
       total_words=total_words+1;
       if(n==1)uio=31;
     end
     tick(128,0,previous_select,0);
     if(selected!=2)$fatal(1,"Missing actual terminal event LEVEL=%0d",level);
     $display("LEVEL_RATE_PASS,level=%0d,stride=%0d,raw_words=%0d,selected=%0d",level,stride,2*stride,selected);
   end
   $display("LEVELS_PASS,equiv_checks=%0d,equiv_reset_checks=%0d,legal_levels=23,raw_words=%0d,checks=%0d,selected_events=46",equiv.compared,equiv.reset_checks,total_words,checks);$finish;
 end
endmodule
