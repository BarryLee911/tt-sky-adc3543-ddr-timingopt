`timescale 1ns/1ps
module tb_rx;
 reg clk=0, rst_n=0, mark=0;
 reg [6:0] data=0;
 wire [13:0] ob,tc;
 wire ov,tv,oe,te,ol,tl;
 integer checks=0, samples=0, errors=0, i,q,raw;
 adc3542_rx7 #(.INPUT_TWOS_COMPLEMENT(0)) a(clk,rst_n,data,mark,ob,ov,oe,ol);
 adc3542_rx7 #(.INPUT_TWOS_COMPLEMENT(1)) b(clk,rst_n,data,mark,tc,tv,te,tl);
 always #6.25 clk=~clk;
 task tick(input integer m,d,r,v,e,x);
 begin
   @(negedge clk);mark=m;data=d;rst_n=r;
   @(posedge clk);#0.001;
   if(ov!==v[0] || tv!==v[0] || oe!==e[0] || te!==e[0])
       $fatal(1,"RX flags check=%0d got %b/%b expected %0d/%0d",checks,ov,oe,v,e);
   if(v && (ob!==x[13:0] || tc!==(x[13:0]^14'h2000))) $fatal(1,"RX bits check=%0d",checks);
   if(ol!==tl || (v && !ol) || (e && ol)) $fatal(1,"RX lock");
   checks=checks+1;samples=samples+v;errors=errors+e;
 end endtask
 task pair(input integer x);
 begin tick(1,x&127,1,0,0,0);tick(0,x>>7,1,1,0,x);end endtask
 initial begin
   tick(0,0,0,0,0,0);tick(0,42,1,0,0,0); // startup on upper must be ignored
   pair(0);pair(8191);pair(8192);pair(16383);pair(127);pair(16256);
   for(i=0;i<16384;i=i+1) pair(i); // exhaustive bit ordering, including ramp test code
   for(i=0;i<16384;i=i+1)begin q=$urandom_range(0,16383);pair(q);end
   tick(1,17,1,0,0,0);tick(1,19,1,0,1,0);tick(0,99,1,0,0,0);pair(12345);
   tick(0,99,1,0,1,0);pair(256); // missing lower/repeated upper
   tick(1,7,1,0,0,0);tick(1,7,0,0,0,0); // reset in lower half
   tick(0,110,1,0,0,0);pair(8192);
   tick(1,9,1,0,0,0);tick(1,9,0,0,0,0);tick(1,9,1,0,0,0);tick(0,5,1,1,0,649);
   tick(0,5,0,0,0,0);pair(123); // startup on lower
   // Delete an entire 1->0 pair: no marker discontinuity is observable.
   pair(124);pair(126); // 125 is absent; receiver must not invent an error.
   $display("RX_PASS,checks=%0d,samples=%0d,detected_errors=%0d,whole_pair_loss_undetectable=1",checks,samples,errors);
   $finish;
 end
 initial begin #5000000;$fatal(1,"RX timeout");end
endmodule
