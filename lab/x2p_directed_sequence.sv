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
             logic [31:0] rd_addr, int b_delay=0, int r_delay=0,
             int waits=0, int aw_delay=0, int w_delay=0, int ar_delay=0);
    x2p_transaction t;
    t=x2p_transaction::type_id::create(label);
    start_item(t);
    t.cmd=X2P_RW; t.write=1; t.label=label;
    t.addr=wr_addr; t.data=wr_data; t.strb=4'hf; t.id=5;
    t.rd_addr=rd_addr; t.rd_id=9;
    t.b_delay=b_delay; t.r_delay=r_delay;
    t.apb_wait_cycles=waits;
    t.aw_delay=aw_delay; t.w_delay=w_delay; t.ar_delay=ar_delay;
    finish_item(t);
  endtask

  // TC21：多种数据模式、多个地址、写后读回。
  task basic_patterns();
    logic [31:0] patterns[8]='{32'h0,32'hffffffff,32'h55555555,32'haaaaaaaa,
       32'ha5a55a5a,32'h5a5aa5a5,32'h80000000,32'h00000001};
    for (int i=0;i<8;i++) begin
      do_write($sformatf("TC21_pattern%0d_addr0",i),32'h10,patterns[i],.id(i));
      do_write($sformatf("TC21_pattern%0d_addr1",i),32'h14,~patterns[i],.id(i));
      do_read($sformatf("TC21_read%0d_addr0",i),32'h10,.id(i));
      do_read($sformatf("TC21_read%0d_addr1",i),32'h14,.id(i));
    end
  endtask

  // TC22：真正的 rand/constraint 随机化，不依赖手工枚举的数据。
  task constrained_random();
    x2p_transaction t;
    do_write("TC22_seed",32'h20,32'h12345678);
    do_read("TC22_seed_read",32'h20);
    for (int i=0;i<cfg.random_iters;i++) begin
      t=x2p_transaction::type_id::create($sformatf("TC22_random_%0d",i));
      start_item(t);
      if (!t.randomize() with {
        addr inside {[32'h0:32'hc0]};
        size inside {[0:2]};
        b_delay inside {0,1,7,15};
        r_delay inside {0,1,7,15};
        apb_wait_cycles inside {0,1,3,8};
      }) `uvm_fatal("RAND_FAIL","TC22 约束随机化失败")
      t.cmd=t.write?X2P_WRITE:X2P_READ;
      t.label=$sformatf("TC22_random_%0d",i);
      `uvm_info("RAND_ITEM",
        $sformatf("%s %s addr=%08h size=%0d strb=%h id=%h aw/w/ar=%0d/%0d/%0d wait=%0d B/R=%0d/%0d",
          t.label,t.write?"W":"R",t.addr,t.size,t.strb,t.id,t.aw_delay,
          t.w_delay,t.ar_delay,t.apb_wait_cycles,t.b_delay,t.r_delay),UVM_MEDIUM)
      finish_item(t);
      if (t.write)
        do_read($sformatf("TC22_readback_%0d",i),{t.addr[31:2],2'b00},
                .id(t.id),.waits(t.apb_wait_cycles),.r_delay(t.r_delay));
    end
  endtask

  // TC23：首尾寄存器的每个字节通道、半字和随机边界访问。
  task boundary_transfers();
    x2p_transaction t;
    for (int lane=0;lane<4;lane++) begin
      do_write($sformatf("TC23_first_byte%0d",lane),32'h0+lane,
               (32'h80+lane)<<(8*lane),.strb(4'b0001<<lane),.size(0));
      do_read($sformatf("TC23_first_read%0d",lane),32'h0+lane,.size(0));
      do_write($sformatf("TC23_last_byte%0d",lane),32'hfc+lane,
               (32'h90+lane)<<(8*lane),.strb(4'b0001<<lane),.size(0));
      do_read($sformatf("TC23_last_read%0d",lane),32'hfc+lane,.size(0));
    end
    do_write("TC23_first_low_half",32'h0,32'h00001234,.strb(3),.size(1));
    do_write("TC23_first_high_half",32'h2,32'h56780000,.strb(12),.size(1));
    do_write("TC23_last_low_half",32'hfc,32'h0000abcd,.strb(3),.size(1));
    do_write("TC23_last_high_half",32'hfe,32'hef010000,.strb(12),.size(1));
    do_read("TC23_first_word",32'h0);
    do_read("TC23_last_word",32'hfc);
    for (int i=0;i<32;i++) begin
      t=x2p_transaction::type_id::create($sformatf("TC23_random_edge_%0d",i));
      // 禁用 soft 默认集合，让 0xFD..0xFF 和 wait=7 也可被选中。
      t.c_default.constraint_mode(0);
      start_item(t);
      if (!t.randomize() with {
        write==1;
        addr inside {32'h0,32'h1,32'h2,32'h3,32'hf8,32'hf9,32'hfa,32'hfb,
                     32'hfc,32'hfd,32'hfe,32'hff};
        size inside {[0:2]};
        prot inside {3'b000,3'b010};
        aw_delay inside {0,3}; w_delay inside {0,3};
        ar_delay==0; r_delay==0;
        b_delay inside {0,7}; apb_wait_cycles inside {0,1,7};
      }) `uvm_fatal("RAND_FAIL","TC23 边界约束随机化失败")
      t.cmd=X2P_WRITE; t.label=$sformatf("TC23_random_edge_%0d",i);
      finish_item(t);
      do_read($sformatf("TC23_edge_readback_%0d",i),{t.addr[31:2],2'b00},
              .id(t.id),.waits(t.apb_wait_cycles),.r_delay(7));
    end
  endtask

  // TC24：完整 BREADY/RREADY 延迟组合，伴随 AW/W 分离和 APB 等待。
  task ready_backpressure();
    int delays[4]='{0,1,7,15};
    do_write("TC24_read_seed",32'h94,32'h24681357);
    for (int b=0;b<4;b++)
      for (int r=0;r<4;r++) begin
        do_rw($sformatf("TC24_B%0d_R%0d",delays[b],delays[r]),
              32'h90,32'h60000000+(b<<8)+r,32'h94,
              .b_delay(delays[b]),.r_delay(delays[r]),.waits(8),
              .aw_delay(b%2?3:0),.w_delay(b%2?0:3));
        do_read($sformatf("TC24_verify_B%0d_R%0d",b,r),32'h90,.r_delay(1));
      end
  endtask

  // TC25：长 ACCESS 等待及两方向等待的串行累积。
  task pready_long_wait();
    int delays[5]='{0,1,7,15,31};
    for (int i=0;i<5;i++) begin
      do_write($sformatf("TC25_wait%0d_write",delays[i]),32'ha0,
               32'hf0000000+i,.waits(delays[i]),.b_delay(3));
      do_read($sformatf("TC25_wait%0d_read",delays[i]),32'ha0,
              .waits(delays[i]),.r_delay(1));
    end
    do_write("TC25_pair_read_seed",32'ha4,32'h0f0f0f0f);
    do_rw("TC25_pair_wait31",32'ha0,32'haa55aa55,32'ha4,
          .b_delay(15),.r_delay(15),.waits(31));
    do_read("TC25_pair_write_readback",32'ha0);
  endtask

  // TC26：非法地址不丢高位、不别名到合法寄存器，错误后继续正常访问。
  task invalid_address_decode();
    logic [31:0] bad_addr[5]='{32'h100,32'h104,32'h1fc,32'hffff0000,32'hfffffffc};
    do_write("TC26_guard0",32'h0,32'h11223344);
    do_write("TC26_guard1",32'h4,32'h55667788);
    do_write("TC26_guard_last",32'hfc,32'haabbccdd);
    for (int i=0;i<5;i++) begin
      do_write($sformatf("TC26_bad_write%0d",i),bad_addr[i],32'hdead0000+i,
               .id(14),.waits(15),.b_delay(7));
      do_read($sformatf("TC26_bad_read%0d",i),bad_addr[i],
              .id(15),.waits(7),.r_delay(1));
      do_read($sformatf("TC26_no_alias0_%0d",i),32'h0);
      do_read($sformatf("TC26_no_alias1_%0d",i),32'h4);
      do_read($sformatf("TC26_no_alias_last_%0d",i),32'hfc);
    end
    // 与 APB 非法地址错误区别：SIZE 拒绝必须完全没有 APB 访问。
    do_write("TC26_local_SIZE_error",32'h100,32'hffffffff,
             .size(7),.id(15),.waits(31),.b_delay(7));
    do_read("TC26_local_SIZE_read",32'h100,
            .size(7),.id(15),.waits(31),.r_delay(7));
  endtask

  // TC27：两个错误并发、错误/成功混合、延迟错误响应及恢复。
  task pslverr_return();
    int delays[3]='{0,7,31};
    do_write("TC27_normal_seed",32'h84,32'h76543210);
    for (int i=0;i<3;i++) begin
      do_rw($sformatf("TC27_both_errors_wait%0d",delays[i]),
            32'he0,32'hffffffff,32'he4,
            .b_delay(7),.r_delay(15),.waits(delays[i]));
      do_read($sformatf("TC27_error_write_unchanged%0d",i),32'he0);
    end
    do_rw("TC27_write_error_read_ok",32'he0,32'hffffffff,32'h84,
          .b_delay(15),.r_delay(1),.waits(7));
    do_rw("TC27_write_ok_read_error",32'he4,32'hcafebabe,32'he4,
          .b_delay(1),.r_delay(15),.waits(15));
    do_write("TC27_recover_write",32'hb0,32'hdecafbad);
    do_read("TC27_recover_read",32'hb0);
  endtask

  // TC28：每个指定阶段重复复位，随机 1..8 拍脉宽，复位后重新访问。
  task reset_exceptions();
    int saved_reset_cycles;
    x2p_abort_e point;
    saved_reset_cycles=cfg.reset_cycles;
    for (int stage=1;stage<=6;stage++)
      for (int rep=0;rep<2;rep++) begin
        cfg.reset_cycles=$urandom_range(8,1);
        if (stage==1 && rep==0) cfg.reset_cycles=1;
        if (stage==2 && rep==0) cfg.reset_cycles=8;
        do_write($sformatf("TC28_seed_stage%0d_rep%0d",stage,rep),
                 32'h20,32'h12340000+stage*16+rep);
        case(stage)
          1: do_write("TC28_AW_only",32'h20,32'hffffffff,.w_delay(30),
                      .waits(31),.b_delay(15),.abort_at(X2P_AFTER_AW));
          2: do_write("TC28_W_only",32'h20,32'hffffffff,.aw_delay(30),
                      .waits(31),.b_delay(15),.abort_at(X2P_AFTER_W));
          3,4: begin
            point=(stage==3)?X2P_AT_SETUP:X2P_AT_WAIT;
            if (rep==0)
              do_write("TC28_APB_write",32'h20,32'hffffffff,
                       .waits(31),.b_delay(15),.abort_at(point));
            else
              do_read("TC28_APB_read",32'h20,
                      .waits(31),.r_delay(15),.abort_at(point));
          end
          5: do_write("TC28_B_response",32'h20,32'hffffffff,
                      .waits(31),.b_delay(15),.abort_at(X2P_AT_B_STALL));
          6: do_read("TC28_R_response",32'h20,
                     .waits(31),.r_delay(15),.abort_at(X2P_AT_R_STALL));
          default: `uvm_fatal("BAD_STAGE","TC28 无效阶段")
        endcase
        do_read($sformatf("TC28_zero_stage%0d_rep%0d",stage,rep),32'h20);
        do_write($sformatf("TC28_recover_stage%0d_rep%0d",stage,rep),
                 32'h20,32'h80000000+stage*16+rep,.waits(7),.b_delay(1));
        do_read($sformatf("TC28_readback_stage%0d_rep%0d",stage,rep),
                32'h20,.waits(7),.r_delay(7));
      end
    cfg.reset_cycles=saved_reset_cycles;
    do_reset("TC28_repeated_idle_reset0");
    do_reset("TC28_repeated_idle_reset1");
    do_read("TC28_final_zero",32'h20);
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
      21: basic_patterns();
      22: constrained_random();
      23: boundary_transfers();
      24: ready_backpressure();
      25: pready_long_wait();
      26: invalid_address_decode();
      27: pslverr_return();
      28: reset_exceptions();
      default: `uvm_fatal("BAD_CASE","CASE 必须为 0..28")
    endcase
    `uvm_info("CASE_END",$sformatf("TC%02d stimulus completed",tc),UVM_LOW)
  endtask

  task body();
    if (cfg == null) `uvm_fatal("NO_CFG","sequence 缺少 cfg")
    do_reset("initial_reset");
    if (cfg.case_select == 0)
      for (int tc=(cfg.new_only?21:1);tc<=28;tc++) run_case(tc);
    else run_case(cfg.case_select);
  endtask
endclass
