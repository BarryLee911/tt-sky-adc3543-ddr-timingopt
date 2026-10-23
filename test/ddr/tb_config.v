`timescale 1ns/1ps
module tb_config;
 reg clk=0,rst_n=0;
 reg [7:0] ui=0,uio=31;
 wire [7:0] outp,iop,oep;
 integer i,j,level,checks=0;
 tt_um_sine_area_detector_adc3542_ddr_orig #(.HANDOFF_WAIT_CYCLES(8)) dut(ui,outp,uio,iop,oep,1'b1,clk,rst_n);
 wire [7:0] opt_out,opt_io,opt_oe;
 tt_um_sine_area_detector_adc3542_ddr #(.HANDOFF_WAIT_CYCLES(8)) opt(ui,opt_out,uio,opt_io,opt_oe,1'b1,clk,rst_n);
 pin_equiv #(.D(5)) equiv(.clk(clk),.rst_n(rst_n),.ref_uo(outp),.ref_uio(iop),.ref_oe(oep),.opt_uo(opt_out),.opt_uio(opt_io),.opt_oe(opt_oe));
 always #6.25 clk=~clk;
 task reset;
 begin
   @(negedge clk);rst_n=0;uio=31;
   repeat(4)@(negedge clk);
   rst_n=1;
 end endtask
 initial begin
   for(level=1;level<=23;level=level+1)begin
     reset;
     for(i=0;i<32;i=i+1)if(i==0 || i>=24)begin
       uio=i;
       for(j=0;j<12;j=j+1)begin
         @(negedge clk);ui=ui^8'hff;
         if(oep!==8'he0 || dut.config_latched_valid!==0 || dut.history_pointer!==0)
           $fatal(1,"Unsupported LEVEL enabled %0d",i);
         checks=checks+1;
       end
     end
     uio=level;
     repeat(12)@(negedge clk);
     if(oep!==8'he1 || !dut.config_latched_valid || dut.config_level_latched!==level[4:0])
       $fatal(1,"Legal LEVEL failed to latch %0d",level);
     if(dut.decimation_terminal!==((1<<(level-1))-1))$fatal(1,"Divider width %0d",level);
     for(i=0;i<32;i=i+1)begin
       uio=i;@(negedge clk);
       if(oep!==8'he1 || dut.config_level_latched!==level[4:0] ||
          dut.decimation_terminal!==((1<<(level-1))-1))
         $fatal(1,"Configuration changed without reset level=%0d bus=%0d",level,i);
       checks=checks+1;
     end
   end
   $display("CONFIG_PASS,equiv_checks=%0d,equiv_reset_checks=%0d,legal_levels=23,unsupported_levels=9,configuration_checks=%0d",equiv.compared,equiv.reset_checks,checks);$finish;
 end
endmodule
