class x2p_directed_sequence extends uvm_sequence #(x2p_transaction);
  `uvm_object_utils(x2p_directed_sequence)
  x2p_config cfg;
  function new(string name="x2p_directed_sequence");
    super.new(name);
  endfunction

  task do_reset(string label);
    x2p_transaction t;
    t=x2p_transaction::type_id::create(label);
    start_item(t);
    t.cmd=X2P_RESET; t.label=label;
    finish_item(t);
  endtask
  task do_write(string label, logic [31:0] addr, logic [31:0] data,
                logic [3:0] strb=4'hf, logic [2:0] size=2,
                int id=3, logic [2:0] prot=0,
                int aw_delay=0, int w_delay=0, int waits=0, int b_delay=0,
                x2p_abort_e abort_at=X2P_NO_ABORT);
    x2p_transaction t;
    t=x2p_transaction::type_id::create(label);
    start_item(t);
    t.cmd=X2P_WRITE; t.write=1; t.label=label;
    t.addr=addr; t.data=data; t.strb=strb; t.size=size; t.id=id; t.prot=prot;
    t.aw_delay=aw_delay; t.w_delay=w_delay; t.apb_wait_cycles=waits;
    t.b_delay=b_delay; t.abort_at=abort_at;
    finish_item(t);
  endtask
  task do_read(string label, logic [31:0] addr, logic [2:0] size=2,
               int id=3, logic [2:0] prot=0,
               int ar_delay=0, int waits=0, int r_delay=0,
               x2p_abort_e abort_at=X2P_NO_ABORT);
    x2p_transaction t;
    t=x2p_transaction::type_id::create(label);
    start_item(t);
    t.cmd=X2P_READ; t.write=0; t.label=label;
    t.addr=addr; t.size=size; t.id=id; t.prot=prot; t.strb=0;
    t.ar_delay=ar_delay; t.apb_wait_cycles=waits;
    t.r_delay=r_delay; t.abort_at=abort_at;
    finish_item(t);
  endtask
  task do_rw(string label, logic [31:0] wr_addr, logic [31:0] wr_data,
             logic [31:0] rd_addr, int b_delay=0, int r_delay=0);
    x2p_transaction t;
    t=x2p_transaction::type_id::create(label);
    start_item(t);
    t.cmd=X2P_RW; t.write=1; t.label=label;
    t.addr=wr_addr; t.data=wr_data; t.strb=4'hf; t.id=5;
    t.rd_addr=rd_addr; t.rd_id=9;
    t.b_delay=b_delay; t.r_delay=r_delay;
    finish_item(t);
  endtask

  task run_case(int tc);
    int waits;
    `uvm_info("CASE_BEGIN",$sformatf("TC%02d",tc),UVM_LOW)
    case (tc)
      1: begin
        do_reset("TC01_reset");
        do_read("TC01_reset_zero",32'h20);
      end
      2: begin
        do_write("TC02_write",32'h20,32'ha5a55a5a);
        do_read("TC02_read",32'h20);
      end
      3: begin
        do_write("TC03_AW_first",32'h24,32'h12345678,.w_delay(3));
        do_read("TC03_read",32'h24);
      end
      4: begin
        do_write("TC04_W_first",32'h28,32'h89abcdef,.aw_delay(3));
        do_read("TC04_read",32'h28);
      end
      5: begin
        // 本 DUT 同方向深度为 1，连续访问在上一响应完成后发起。
        for (int i=0;i<8;i++)
          do_write($sformatf("TC05_write_%0d",i),32'h40+4*i,32'h10203040+i);
        for (int i=0;i<8;i++)
          do_read($sformatf("TC05_read_%0d",i),32'h40+4*i);
      end
      6: begin
        for (int mask=0;mask<16;mask++) begin
          do_write($sformatf("TC06_seed_%0d",mask),32'h60,32'h11223344);
          do_write($sformatf("TC06_mask_%0d",mask),32'h60,32'haabbccdd,mask);
          do_read($sformatf("TC06_read_%0d",mask),32'h60);
        end
      end
      7: begin
        do_write("TC07_seed",32'h20,32'h11223344);
        do_write("TC07_byte",32'h21,32'h0000ab00,.strb(4'b0010),.size(0));
        do_read("TC07_byte_read",32'h21,.size(0));
        do_write("TC07_halfword",32'h22,32'hcdef0000,.strb(4'b1100),.size(1));
        do_read("TC07_halfword_read",32'h22,.size(1));
        do_read("TC07_full_read",32'h20);
      end
      8: begin
        do_write("TC08_first",32'h0,32'h55aa55aa);
        do_write("TC08_last",32'hfc,32'haa55aa55);
        do_read("TC08_first_read",32'h0);
        do_read("TC08_last_read",32'hfc);
        do_read("TC08_unaligned_narrow",32'h21,.size(0));
        do_read("TC08_high_address",32'hfffffffc);
      end
      9: begin
        for (int i=0;i<4;i++) begin
          case(i) 0:waits=0; 1:waits=1; 2:waits=3; 3:waits=8; endcase
          do_write($sformatf("TC09_write_wait%0d",waits),32'h30,
                   32'h76543210+i,.waits(waits));
          do_read($sformatf("TC09_read_wait%0d",waits),32'h30,.waits(waits));
        end
      end
      10: begin
        do_write("TC10_secure_write",32'h34,32'h01020304,.prot(3'b000));
        do_read("TC10_secure_read",32'h34,.prot(3'b000));
        do_write("TC10_nonsecure_write",32'h34,32'h05060708,.prot(3'b010));
        do_read("TC10_nonsecure_read",32'h34,.prot(3'b010));
      end
      11: begin
        do_write("TC11_B_stall3",32'h38,32'h33333333,.b_delay(3));
        do_read("TC11_read3",32'h38);
        do_write("TC11_B_stall8",32'h38,32'h88888888,.b_delay(8));
        do_read("TC11_read8",32'h38);
      end
      12: begin
        do_write("TC12_seed",32'h3c,32'hfeedc0de);
        do_read("TC12_R_stall3",32'h3c,.r_delay(3));
        do_read("TC12_R_stall8",32'h3c,.r_delay(8));
      end
      13: begin
        do_read("TC13_E0_before",32'he0);
        do_write("TC13_write_error",32'he0,32'hffffffff);
        do_read("TC13_E0_unchanged",32'he0);
        do_write("TC13_seed_E4",32'he4,32'h12345678);
        do_read("TC13_read_error",32'he4);
        do_write("TC13_write_error_wait3",32'he0,32'habcdef01,.waits(3));
        do_read("TC13_read_error_wait3",32'he4,.waits(3));
        do_read("TC13_E0_still_zero",32'he0);
      end
      14: begin
        do_write("TC14_bad_address_write",32'h100,32'hdeadbeef);
        do_read("TC14_bad_address_read",32'h100);
      end
      15: begin
        for (int sz=3;sz<=7;sz++) begin
          do_write($sformatf("TC15_SIZE%0d_write",sz),32'h20,
                   32'hffffffff,.size(sz),.id(sz));
          do_read($sformatf("TC15_SIZE%0d_read",sz),32'h20,.size(sz),.id(sz));
        end
      end
      16: begin
        for (int id=0;id<(1<<`X2P_ID_WIDTH);id++) begin
          do_write($sformatf("TC16_ID%0d_write",id),32'h70,
                   32'h10000000+id,.id(id),.b_delay(3));
          do_read($sformatf("TC16_ID%0d_read",id),32'h70,.id(id),.r_delay(3));
        end
      end
      17: begin
        do_write("TC17_seed_read_addr",32'h84,32'h24681357);
        do_read("TC17_prepare_write_priority",32'h84);
        do_rw("TC17_both_write_priority",32'h80,32'h11112222,32'h84,3,8);
        do_write("TC17_prepare_read_priority",32'h8c,32'h9999aaaa);
        do_rw("TC17_both_read_priority",32'h88,32'h33334444,32'h84,8,3);
        do_read("TC17_verify_write0",32'h80);
        do_read("TC17_verify_write1",32'h88);
      end
      18: begin
        do_write("TC18_AW_only_reset",32'h20,32'hffffffff,
                 .w_delay(20),.abort_at(X2P_AFTER_AW));
        do_read("TC18_after_AW_reset",32'h20);
        do_write("TC18_W_only_reset",32'h20,32'hffffffff,
                 .aw_delay(20),.abort_at(X2P_AFTER_W));
        do_write("TC18_recover_write",32'h20,32'h13572468);
        do_read("TC18_recover_read",32'h20);
      end
      19: begin
        do_write("TC19_W_SETUP_reset",32'h20,32'hffffffff,
                 .abort_at(X2P_AT_SETUP));
        do_read("TC19_after_W_SETUP",32'h20);
        do_write("TC19_W_WAIT_reset",32'h20,32'hffffffff,
                 .waits(8),.abort_at(X2P_AT_WAIT));
        do_read("TC19_after_W_WAIT",32'h20);
        do_read("TC19_R_SETUP_reset",32'h20,.abort_at(X2P_AT_SETUP));
        do_read("TC19_after_R_SETUP",32'h20);
        do_read("TC19_R_WAIT_reset",32'h20,.waits(8),.abort_at(X2P_AT_WAIT));
        do_read("TC19_after_R_WAIT",32'h20);
      end
      20: begin
        do_write("TC20_B_reset",32'h20,32'ha5a55a5a,
                 .b_delay(12),.abort_at(X2P_AT_B_STALL));
        do_read("TC20_after_B_reset",32'h20);
        do_write("TC20_R_seed",32'h20,32'h11223344);
        do_read("TC20_R_reset",32'h20,.r_delay(12),.abort_at(X2P_AT_R_STALL));
        do_read("TC20_after_R_reset",32'h20);
      end
      default: `uvm_fatal("BAD_CASE","CASE 必须为 0..20")
    endcase
    `uvm_info("CASE_END",$sformatf("TC%02d stimulus completed",tc),UVM_LOW)
  endtask

  task body();
    if (cfg == null) `uvm_fatal("NO_CFG","sequence 缺少 cfg")
    do_reset("initial_reset");
    if (cfg.case_select == 0)
      for (int tc=1;tc<=20;tc++) run_case(tc);
    else run_case(cfg.case_select);
  endtask
endclass
