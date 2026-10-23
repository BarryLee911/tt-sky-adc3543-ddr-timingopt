`timescale 1ns/1ps
// Source-synchronous behavioural model: DCLK/data launched around the SAME edges.
// Aperture guard reports violations even when lucky data values decode correctly.
module tb_timing;
 localparam real H=12.5;
 reg clk=0,rst_n=0,mark=0;
 reg [6:0] data=0;
 wire [13:0] sample14;
 wire valid,err,locked;
 adc3542_rx7 rx(clk,rst_n,data,mark,sample14,valid,err,locked);
 real phase=11.5,tpd=5,extra=0,skew=0,duty=0;
 real last_m=-1000,last_d=-1000,next_m,next_d,now_t,min_setup=1000,min_hold=1000,sm,hm;
 integer mi=-1,di=-1,k,d,m,capture,idx,previous=-1,checks=0,bad=0,aperture=0;
 function integer code(input integer n);
   code=(1234+n*7919+n*n*17)&16383;
 endfunction
 function real edge_at(input integer n);
   edge_at=n*H+tpd+extra+((n%2) ? duty:0);
 endfunction
 initial begin
   m=$value$plusargs("PHASE=%f",phase);m=$value$plusargs("TPD=%f",tpd);
   m=$value$plusargs("EXTRA=%f",extra);m=$value$plusargs("SKEW=%f",skew);m=$value$plusargs("DUTY=%f",duty);
   fork
     begin
       for(k=0;k<260;k=k+1)begin
         #(edge_at(k)-$realtime);mark=(k%2)==0;mi=k;last_m=$realtime;
       end
     end
     begin
       for(d=0;d<260;d=d+1)begin
         #(edge_at(d)+skew-$realtime);
         data=((code(d/2)^8192)>>((d%2)*7))&127;di=d;last_d=$realtime;
       end
     end
     begin
       // Exercise synchronous reset at an actual clock edge before the phase sweep.
       #0.5;clk=1;#0.5;clk=0;
       #(H-1.0);rst_n=1;
       #(H+phase);
       for(capture=0;capture<250;capture=capture+1)begin
         clk=1;
         now_t=$realtime;next_m=edge_at(mi+1);next_d=edge_at(di+1)+skew;
         sm=now_t-((last_m>last_d) ? last_m:last_d);
         hm=((next_m<next_d) ? next_m:next_d)-now_t;
         if(sm<min_setup)min_setup=sm;
         if(hm<min_hold)min_hold=hm;
         // Illustrative receiver setup=1ns, hold=.5ns, clock uncertainty=.5ns.
         if(sm<1.5 || hm<1.0)aperture=aperture+1;
         idx=mi/2;
         #0.001;
         if(err)bad=bad+1;
         if(valid)begin
           checks=checks+1;
           if(sample14!==code(idx) || (previous>=0 && idx!=previous+1))bad=bad+1;
           previous=idx;
         end
         #(H/2-0.001);clk=0;#(H/2);
       end
       $display("TIMING_RESULT,checks=%0d,bad=%0d,aperture=%0d,setup_ns=%0.3f,hold_ns=%0.3f",checks,bad,aperture,min_setup,min_hold);
       $finish;
     end
   join
 end
endmodule
