`timescale 1ns/1ps
// Source tasks specify expected sample events independently of DUT state.
// Output oracle uses only that source schedule and integer arithmetic.
module tb_stream;
 parameter integer HANDOFF=80000;
 parameter integer TWOS=1;
 parameter integer LEVEL=1;
 localparam integer STRIDE=1<<(LEVEL-1);
 reg clk=0,rst_n=0,controller_drives=1;
 reg [7:0] ui=0;
 reg [4:0] config_bus=31;
 tri pad0;
 wire [7:0] outp,iop,oep,oldout,oldio,oldoe;
 wire [7:0] inp={3'b0,config_bus[4:1],pad0};
 assign pad0=controller_drives ? config_bus[0] : 1'bz;
 assign pad0=oep[0] ? iop[0] : 1'bz;
 wire [10:0] word={iop[7:5],outp};
 // dut = unmodified reference build (all original internal checks below apply to it)
 tt_um_sine_area_detector_adc3542_ddr_orig #(.HANDOFF_WAIT_CYCLES(HANDOFF),.INPUT_TWOS_COMPLEMENT(TWOS)) dut(
 .ui_in(ui),.uo_out(outp),.uio_in(inp),.uio_out(iop),.uio_oe(oep),.ena(1'b1),.clk(clk),.rst_n(rst_n));
 // opt = timing-optimized build; checked pin-for-pin against dut, 5 cycles later
 wire [7:0] opt_out,opt_io,opt_oe;
 tt_um_sine_area_detector_adc3542_ddr #(.HANDOFF_WAIT_CYCLES(HANDOFF),.INPUT_TWOS_COMPLEMENT(TWOS)) opt(
 .ui_in(ui),.uo_out(opt_out),.uio_in(inp),.uio_out(opt_io),.uio_oe(opt_oe),.ena(1'b1),.clk(clk),.rst_n(rst_n));
 pin_equiv #(.D(5)) equiv(.clk(clk),.rst_n(rst_n),.ref_uo(outp),.ref_uio(iop),.ref_oe(oep),.opt_uo(opt_out),.opt_uio(opt_io),.opt_oe(opt_oe));
 tt_um_sine_area_detector_12bit #(.HANDOFF_WAIT_CYCLES(HANDOFF)) old(
 .ui_in(ui),.uo_out(oldout),.uio_in(inp),.uio_out(oldio),.uio_oe(oldoe),.ena(1'b1),.clk(clk),.rst_n(rst_n));
 always #6.25 clk=~clk;
 reg [7:0] bytes[0:4194303];
 integer ev=0,ee=0,eq=8192,pv=0,pe=0,pq=8192,configured=0;
 wire ref_reset = rst_n && configured && !pe;
 reg [21:0] ref_phase=0;
 wire ref_valid = pv && ref_reset && (ref_phase==STRIDE-1);
 always @(posedge clk)begin
   if(!ref_reset)ref_phase<=0;
   else if(pv)ref_phase <= (ref_phase==STRIDE-1) ? 0 : ref_phase+1;
 end
 wire [13:0] ref_sample=pq;
 wire [24:0] ref_sum;
 wire [28:0] ref_sum16;
 wire ref_bv,ref_sv;
 meanabs_candidate #(.INPUT_BITS(14)) full_parallel_reference(
 .clk(clk),.rst_n(ref_reset),.sample_valid(ref_valid),.sample(ref_sample),
 .result_sum(ref_sum),.result_valid(ref_bv),.result_sum16(ref_sum16),.result16_valid(ref_sv));
 integer hist[0:2047],ring[0:15];
 integer pos=0,count=0,bpos=0,bsum=0,blocks=0,rpos=0,s16=0;
 integer latest=0,ready=0,prev_sv=0,prev_s16=0;
 integer count_before,latest_before,ready_before,run_before,expect_bv,expect_sv,expect_bs,expect_s16;
 integer part=0,assembled=0,snapshot=0,frame_open=0;
 integer edges=0,accepted=0,count_checks=0,frames=0,invalids=0,updates_open=0,error_count=0,resets=0;
 integer max_sum16=0,remainder_mask=0,signbit,agree,mag,j,tag,payload,expect_handoff=0,config_age=0;
 integer n,fd,got,faults=0,idx,q,raw,boot;
 integer raw_since_reset=0,selected_since_reset=0;
 string input_file;
 task tick(input integer bus,v,e,x,r);
 begin
   @(negedge clk);ui=bus;ev=v;ee=e;eq=x;rst_n=r;
   if(configured && config_age>=3) controller_drives=0;
   @(posedge clk);#0.01;
 end endtask
 task pair(input integer x);
 begin
   raw=x^(TWOS ? 8192:0);
   tick(128|(raw&127),0,0,0,1);tick(raw>>7,1,0,x,1);
 end endtask
 always @(posedge clk) begin
   edges=edges+1;
   count_before=count;latest_before=latest;ready_before=ready;
   run_before=rst_n && configured && !pe;
   if(dut.backend_process !== (run_before && pv && ((raw_since_reset+1)%STRIDE==0)))
     $fatal(1,"Independent sample selection level=%0d edge=%0d",LEVEL,edges);
   expect_bv=0;expect_sv=0;
   if(!run_before) begin
     pos=0;count=0;bpos=0;bsum=0;blocks=0;rpos=0;s16=0;latest=0;ready=0;prev_sv=0;
     raw_since_reset=0;selected_since_reset=0;
     part=0;frame_open=0;
     for(j=0;j<2048;j=j+1)hist[j]=0;
     for(j=0;j<16;j=j+1)ring[j]=0;
   end else begin
     if(prev_sv) begin
       latest=prev_s16>>2;ready=1;
       if(frame_open)updates_open=updates_open+1;
     end
     if(pv) begin
       raw_since_reset=raw_since_reset+1;
       if(raw_since_reset%STRIDE==0)begin
       selected_since_reset=selected_since_reset+1;
       agree=((pq>=8192)==(pos>=1024));
       count=count+agree-hist[pos];hist[pos]=agree;pos=(pos+1)%2048;
       mag=pq>=8192 ? pq-8192:8192-pq;
       bsum=bsum+mag;bpos=bpos+1;accepted=accepted+1;
       if(bpos==2048)begin
         expect_bv=1;expect_bs=bsum;
         s16=s16+bsum-ring[rpos];ring[rpos]=bsum;rpos=(rpos+1)%16;
         blocks=blocks+1;bpos=0;bsum=0;
         if(blocks>=16)begin
           expect_sv=1;expect_s16=s16;
           if(s16>max_sum16)max_sum16=s16;
           remainder_mask=remainder_mask | (1<<(s16%4));
         end
       end
       end
     end
     prev_sv=expect_sv;prev_s16=s16;
   end
   if(!rst_n)begin configured=0;config_age=0;expect_handoff=0;end
   else if(!configured && config_bus==LEVEL) begin configured=1;config_age=0;end
   else if(configured) begin
     config_age=config_age+1;
     if(config_age==HANDOFF)expect_handoff=1;
   end
   #0.001;
   if((^{outp,iop,oep})===1'bx) $fatal(1,"Unknown output edge %0d",edges);
   if(oep!==oldoe || iop[0]!==oldio[0])$fatal(1,"12-bit TYPE/OE schedule changed edge %0d",edges);
   if(oep!==(expect_handoff ? 8'he1:8'he0))$fatal(1,"Handoff length");
   if(oep[4:1]!==0 || iop[4:1]!==0 || (controller_drives && oep[0]))$fatal(1,"Pad contention");
   if(dut.sample_valid!==ev[0] || dut.rx_error!==ee[0])$fatal(1,"Source/RX event mismatch edge %0d",edges);
   if(ev && dut.sample14!==eq[13:0])$fatal(1,"Recovered sample mismatch edge %0d",edges);
   if(dut.amplitude_valid!==expect_bv[0] || dut.amplitude16_valid!==expect_sv[0])$fatal(1,"Integer result cadence");
   if(ref_bv!==dut.amplitude_valid || ref_sv!==dut.amplitude16_valid || ref_sum!==dut.amplitude_sum || ref_sum16!==dut.amplitude_sum16)$fatal(1,"Full14 parallel reference mismatch");
   if(expect_bv && dut.amplitude_sum!==expect_bs[24:0])$fatal(1,"Integer block sum");
   if(expect_sv && dut.amplitude_sum16!==expect_s16[28:0])$fatal(1,"Integer 16-period sum");
   if(rst_n && !iop[0])begin
     if(word!==(run_before ? (count_before>2047 ? 11'd2047:count_before[10:0]):11'd0))$fatal(1,"Pin COUNT mismatch edge %0d",edges);
     count_checks=count_checks+1;
   end
   if(rst_n && oep[0] && iop[0])begin
     tag=word[10:9];payload=word[8:0];
     if(!run_before || !ready_before)begin
       if(tag!=3)$fatal(1,"Invalid window exposed as valid edge %0d",edges);
       part=0;frame_open=0;invalids=invalids+1;
     end else begin
       if(tag!=part)$fatal(1,"Fragment order edge %0d got %0d expected %0d",edges,tag,part);
       if(tag==0)begin snapshot=latest_before;assembled=payload;frame_open=1;part=1;end
       else if(tag==1)begin assembled=assembled|(payload<<9);part=2;end
       else begin
         assembled=assembled|(payload<<18);
         if(assembled!=snapshot)$fatal(1,"Pin amplitude / atomic snapshot mismatch edge %0d",edges);
         frames=frames+1;part=0;frame_open=0;
       end
     end
   end
   if(ee)error_count=error_count+1;
   pv=ev;pe=ee;pq=eq;
 end
 initial begin
   for(j=0;j<2048;j=j+1)hist[j]=0;
   for(j=0;j<16;j=j+1)ring[j]=0;
   if(!$value$plusargs("INPUT=%s",input_file) || !$value$plusargs("N=%d",n))$fatal(1,"Missing input");
   got=$value$plusargs("FAULTS=%d",faults);
   fd=$fopen(input_file,"rb");got=$fread(bytes,fd,0,2*n);$fclose(fd);
   if(got!=2*n || n>2097152)$fatal(1,"Input length");
   repeat(4)tick(0,0,0,0,0);
   repeat(5)tick(0,0,0,0,1); // illegal configuration 31
   @(negedge clk);config_bus=LEVEL;
   tick(0,0,0,0,1); // latch LEVEL, receiver still reset on this edge
   // First receiver-enabled tick above starts in upper half and is discarded.
   for(idx=0;idx<n;idx=idx+1)begin
     q={bytes[2*idx+1][5:0],bytes[2*idx]};
     if(faults && idx==n/4)begin
       raw=q^(TWOS ? 8192:0);
       tick(128|(raw&127),0,0,0,1);
       tick(128|(raw&127),0,1,0,1); // duplicated lower, pair discarded
       tick(raw>>7,0,0,0,1);
     end else if(faults && idx==n/2)begin
       raw=q^(TWOS ? 8192:0);
       tick(raw>>7,0,1,0,1); // lower missing -> repeated upper
     end else if(faults && idx==3*n/4)begin
       raw=q^(TWOS ? 8192:0);
       tick(128|(raw&127),0,0,0,1);
       repeat(3)tick(0,0,0,0,0);
       @(negedge clk);controller_drives=1;config_bus=LEVEL;
       tick(0,0,0,0,1);
       tick(raw>>7,0,0,0,1); // reset interrupts half: stale lower cannot survive
       resets=resets+1;
     end else pair(q);
   end
   // Flush pipeline with four benign complete samples.
   repeat(4)pair(8192);
   if(frames<1 || count_checks<100 || equiv.compared<edges/2 || (faults && (error_count!=2 || resets!=1 || invalids<1)))$fatal(1,"Coverage");
   $display("STREAM_PASS,equiv_checks=%0d,equiv_reset_checks=%0d,level=%0d,edges=%0d,accepted=%0d,count_checks=%0d,frames=%0d,invalids=%0d,updates_open=%0d,errors=%0d,resets=%0d,max_sum16=%0d,remainder_mask=%0d",equiv.compared,equiv.reset_checks,LEVEL,edges,accepted,count_checks,frames,invalids,updates_open,error_count,resets,max_sum16,remainder_mask);
   $finish;
 end
 initial begin #75000000;$fatal(1,"Stream timeout");end
endmodule
