class x2p_axi_driver extends uvm_driver #(x2p_transaction);
  `uvm_component_utils(x2p_axi_driver)
  x2p_config cfg;
  x2p_vif_t vif;
  bit abort_in_progress, aw_accepted, w_accepted;

  covergroup reset_cg with function sample(int point);
    option.per_instance = 1;
    cp_stage: coverpoint point {
      bins initial_or_idle = {0}; bins aw_only = {1}; bins w_only = {2};
      bins setup = {3}; bins access_wait = {4};
      bins b_stall = {5}; bins r_stall = {6};
    }
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    reset_cg = new();
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(x2p_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NO_CFG", "AXI driver 缺少 cfg")
    vif = cfg.vif;
  endfunction

  // 调用者必须已经位于 axi_drv_cb 的下降沿。
  task drive_idle();
    vif.axi_drv_cb.s_axi_awvalid <= 0;
    vif.axi_drv_cb.s_axi_wvalid  <= 0;
    vif.axi_drv_cb.s_axi_arvalid <= 0;
    vif.axi_drv_cb.s_axi_bready  <= 0;
    vif.axi_drv_cb.s_axi_rready  <= 0;
    vif.axi_drv_cb.s_axi_awaddr <= 0;
    vif.axi_drv_cb.s_axi_awid <= 0;
    vif.axi_drv_cb.s_axi_awsize <= 2;
    vif.axi_drv_cb.s_axi_awprot <= 0;
    vif.axi_drv_cb.s_axi_wdata <= 0;
    vif.axi_drv_cb.s_axi_wstrb <= 0;
    vif.axi_drv_cb.s_axi_araddr <= 0;
    vif.axi_drv_cb.s_axi_arid <= 0;
    vif.axi_drv_cb.s_axi_arsize <= 2;
    vif.axi_drv_cb.s_axi_arprot <= 0;
  endtask

  task reset_now(x2p_abort_e point=X2P_NO_ABORT);
    abort_in_progress = 1;
    reset_cg.sample(int'(point));
    vif.epoch = vif.epoch + 1;
    drive_idle();
    vif.axi_drv_cb.aresetn <= 0;
    repeat (cfg.reset_cycles) @(vif.axi_drv_cb);
    vif.axi_drv_cb.aresetn <= 1;
    repeat (2) @(vif.mon_cb);
  endtask

  task send_aw(x2p_transaction t);
    repeat (t.aw_delay) begin
      @(vif.axi_drv_cb);
      if (abort_in_progress) return;
    end
    @(vif.axi_drv_cb);
    if (abort_in_progress) return;
    vif.axi_drv_cb.s_axi_awaddr <= t.addr;
    vif.axi_drv_cb.s_axi_awid <= t.id;
    vif.axi_drv_cb.s_axi_awsize <= t.size;
    vif.axi_drv_cb.s_axi_awprot <= t.prot;
    vif.axi_drv_cb.s_axi_awvalid <= 1;
    forever begin
      @(vif.mon_cb);
      if (abort_in_progress) return;
      if (vif.mon_cb.s_axi_awvalid === 1'b1 &&
          vif.mon_cb.s_axi_awready === 1'b1) break;
    end
    aw_accepted = 1;
    @(vif.axi_drv_cb);
    if (!abort_in_progress) vif.axi_drv_cb.s_axi_awvalid <= 0;
  endtask

  task send_w(x2p_transaction t);
    repeat (t.w_delay) begin
      @(vif.axi_drv_cb);
      if (abort_in_progress) return;
    end
    @(vif.axi_drv_cb);
    if (abort_in_progress) return;
    vif.axi_drv_cb.s_axi_wdata <= t.data;
    vif.axi_drv_cb.s_axi_wstrb <= t.strb;
    vif.axi_drv_cb.s_axi_wvalid <= 1;
    forever begin
      @(vif.mon_cb);
      if (abort_in_progress) return;
      if (vif.mon_cb.s_axi_wvalid === 1'b1 &&
          vif.mon_cb.s_axi_wready === 1'b1) break;
    end
    w_accepted = 1;
    @(vif.axi_drv_cb);
    if (!abort_in_progress) vif.axi_drv_cb.s_axi_wvalid <= 0;
  endtask

  task send_ar(x2p_transaction t);
    repeat (t.ar_delay) begin
      @(vif.axi_drv_cb);
      if (abort_in_progress) return;
    end
    @(vif.axi_drv_cb);
    if (abort_in_progress) return;
    vif.axi_drv_cb.s_axi_araddr <= (t.cmd == X2P_RW) ? t.rd_addr : t.addr;
    vif.axi_drv_cb.s_axi_arid   <= (t.cmd == X2P_RW) ? t.rd_id   : t.id;
    vif.axi_drv_cb.s_axi_arsize <= (t.cmd == X2P_RW) ? t.rd_size : t.size;
    vif.axi_drv_cb.s_axi_arprot <= (t.cmd == X2P_RW) ? t.rd_prot : t.prot;
    vif.axi_drv_cb.s_axi_arvalid <= 1;
    forever begin
      @(vif.mon_cb);
      if (abort_in_progress) return;
      if (vif.mon_cb.s_axi_arvalid === 1'b1 &&
          vif.mon_cb.s_axi_arready === 1'b1) break;
    end
    @(vif.axi_drv_cb);
    if (!abort_in_progress) vif.axi_drv_cb.s_axi_arvalid <= 0;
  endtask

  task receive_b(x2p_transaction t);
    if (t.b_delay != 0) begin
      forever begin
        @(vif.mon_cb);
        if (abort_in_progress) return;
        if (vif.mon_cb.s_axi_bvalid === 1'b1) break;
      end
      // 第一次观察到 VALID 的采样拍已经是第 1 个反压周期。
      repeat (t.b_delay-1) begin
        @(vif.mon_cb);
        if (abort_in_progress) return;
      end
      @(vif.axi_drv_cb);
      if (abort_in_progress) return;
      vif.axi_drv_cb.s_axi_bready <= 1;
    end
    forever begin
      @(vif.mon_cb);
      if (abort_in_progress) return;
      if (vif.mon_cb.s_axi_bvalid === 1'b1 &&
          vif.mon_cb.s_axi_bready === 1'b1) break;
    end
    @(vif.axi_drv_cb);
    if (!abort_in_progress) vif.axi_drv_cb.s_axi_bready <= 0;
  endtask

  task receive_r(x2p_transaction t);
    if (t.r_delay != 0) begin
      forever begin
        @(vif.mon_cb);
        if (abort_in_progress) return;
        if (vif.mon_cb.s_axi_rvalid === 1'b1) break;
      end
      repeat (t.r_delay-1) begin
        @(vif.mon_cb);
        if (abort_in_progress) return;
      end
      @(vif.axi_drv_cb);
      if (abort_in_progress) return;
      vif.axi_drv_cb.s_axi_rready <= 1;
    end
    forever begin
      @(vif.mon_cb);
      if (abort_in_progress) return;
      if (vif.mon_cb.s_axi_rvalid === 1'b1 &&
          vif.mon_cb.s_axi_rready === 1'b1) break;
    end
    @(vif.axi_drv_cb);
    if (!abort_in_progress) vif.axi_drv_cb.s_axi_rready <= 0;
  endtask

  task run_channels(x2p_transaction t);
    fork
      begin
        if (t.cmd == X2P_WRITE || t.cmd == X2P_RW) send_aw(t);
      end
      begin
        if (t.cmd == X2P_WRITE || t.cmd == X2P_RW) send_w(t);
      end
      begin
        if (t.cmd == X2P_WRITE || t.cmd == X2P_RW) receive_b(t);
      end
      begin
        if (t.cmd == X2P_READ || t.cmd == X2P_RW) send_ar(t);
      end
      begin
        if (t.cmd == X2P_READ || t.cmd == X2P_RW) receive_r(t);
      end
    join
  endtask

  task wait_abort_point(x2p_abort_e point);
    bit hit;
    forever begin
      @(vif.axi_drv_cb);
      hit = 0;
      case (point)
        X2P_AFTER_AW: hit = aw_accepted && !w_accepted;
        X2P_AFTER_W:  hit = w_accepted && !aw_accepted;
        X2P_AT_SETUP: hit = vif.axi_drv_cb.m_apb_psel === 1'b1 &&
                           vif.axi_drv_cb.m_apb_penable === 1'b0;
        X2P_AT_WAIT:  hit = vif.axi_drv_cb.m_apb_psel === 1'b1 &&
                           vif.axi_drv_cb.m_apb_penable === 1'b1 &&
                           vif.axi_drv_cb.m_apb_pready === 1'b0;
        X2P_AT_B_STALL: hit = vif.axi_drv_cb.s_axi_bvalid === 1'b1 &&
                             vif.s_axi_bready === 1'b0;
        X2P_AT_R_STALL: hit = vif.axi_drv_cb.s_axi_rvalid === 1'b1 &&
                             vif.s_axi_rready === 1'b0;
        default: `uvm_fatal("BAD_ABORT", "无效复位触发条件")
      endcase
      if (hit) return;
    end
  endtask

  task execute(x2p_transaction t);
    bit work_done, reset_done;
    work_done = 0;
    reset_done = 0;
    abort_in_progress = 0;
    aw_accepted = 0;
    w_accepted = 0;
    @(vif.axi_drv_cb);
    drive_idle();
    vif.axi_drv_cb.s_axi_bready <=
        ((t.cmd == X2P_WRITE || t.cmd == X2P_RW) && t.b_delay == 0);
    vif.axi_drv_cb.s_axi_rready <=
        ((t.cmd == X2P_READ || t.cmd == X2P_RW) && t.r_delay == 0);
    fork : job_threads
      begin
        run_channels(t);
        if (t.abort_at != X2P_NO_ABORT) begin
          if (!abort_in_progress)
            `uvm_fatal("MISSED_RESET", "传输已结束，却没有触发预定复位")
          wait (reset_done);
        end
        work_done = 1;
      end
      begin
        if (t.abort_at != X2P_NO_ABORT) begin
          wait_abort_point(t.abort_at);
          // SETUP 触发后在当前下降沿立即复位。
          reset_now(t.abort_at);
          reset_done = 1;
        end else begin
          wait (work_done);
        end
      end
      begin
        repeat (cfg.item_timeout) @(vif.mon_cb);
        `uvm_fatal("ITEM_TIMEOUT",
                   $sformatf("%s 超过 %0d 拍", t.label, cfg.item_timeout))
      end
    join_any
    disable job_threads;
    t.aborted = reset_done;
    @(vif.axi_drv_cb);
    drive_idle();
  endtask

  task run_phase(uvm_phase phase);
    @(vif.axi_drv_cb);
    drive_idle();
    forever begin
      seq_item_port.get_next_item(req);
      cfg.apb_wait_cycles = req.apb_wait_cycles;
      cfg.b_stall_cycles = req.b_delay;
      cfg.r_stall_cycles = req.r_delay;
      if (req.cmd == X2P_RESET) begin
        @(vif.axi_drv_cb);
        reset_now();
      end else begin
        execute(req);
      end
      `uvm_info("AXI_DRIVER",
                $sformatf("%s %s", req.label,
                          req.aborted ? "ABORTED" : "DONE"), UVM_MEDIUM)
      seq_item_port.item_done();
    end
  endtask
  function void report_phase(uvm_phase phase);
    `uvm_info("RESET_COVERAGE",
              $sformatf("coverage=%.2f%%",reset_cg.get_inst_coverage()),UVM_LOW)
  endfunction
endclass
