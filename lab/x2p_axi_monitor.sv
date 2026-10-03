class x2p_axi_monitor extends uvm_monitor;
  `uvm_component_utils(x2p_axi_monitor)
  x2p_config cfg;
  x2p_vif_t vif;
  uvm_blocking_put_port #(x2p_transaction) req_put, rsp_put;
  protected x2p_transaction aw_q[$], w_q[$], wr_q[$], rd_q[$];
  protected int unsigned wr_ordinal, rd_ordinal, b_stalls, r_stalls;
  longint unsigned cycle;
  int unsigned aw_count, w_count, ar_count, b_count, r_count;
  int unsigned aborted_partial, aborted_requests;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(x2p_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NO_CFG", "AXI monitor 缺少 cfg")
    vif = cfg.vif;
    req_put = new("req_put", this);
    rsp_put = new("rsp_put", this);
  endfunction
  function int pending_count();
    return aw_q.size()+w_q.size()+wr_q.size()+rd_q.size();
  endfunction
  function void clear_pending();
    aborted_partial += aw_q.size()+w_q.size();
    aborted_requests += wr_q.size()+rd_q.size();
    aw_q.delete(); w_q.delete(); wr_q.delete(); rd_q.delete();
    wr_ordinal = 0; rd_ordinal = 0;
    b_stalls = 0; r_stalls = 0;
  endfunction
  function void check_age();
    if (aw_q.size() && cycle-aw_q[0].accepted_cycle > cfg.item_timeout)
      `uvm_fatal("AW_TIMEOUT", "AW 半笔请求超时")
    if (w_q.size() && cycle-w_q[0].accepted_cycle > cfg.item_timeout)
      `uvm_fatal("W_TIMEOUT", "W 半笔请求超时")
    if (wr_q.size() && cycle-wr_q[0].accepted_cycle > cfg.item_timeout)
      `uvm_fatal("B_TIMEOUT", "完整写请求未收到 B 握手")
    if (rd_q.size() && cycle-rd_q[0].accepted_cycle > cfg.item_timeout)
      `uvm_fatal("R_TIMEOUT", "读请求未收到 R 握手")
  endfunction

  task sample_requests();
    x2p_transaction a, w, t;
    if (vif.mon_cb.s_axi_awvalid === 1'b1 &&
        vif.mon_cb.s_axi_awready === 1'b1) begin
      a = x2p_transaction::type_id::create("aw");
      a.addr = vif.mon_cb.s_axi_awaddr;
      a.id = vif.mon_cb.s_axi_awid;
      a.size = vif.mon_cb.s_axi_awsize;
      a.prot = vif.mon_cb.s_axi_awprot;
      a.epoch = vif.mon_cb.epoch;
      a.accepted_cycle = cycle;
      if ($isunknown({a.addr,a.id,a.size,a.prot}))
        `uvm_error("AXI_X", "AW 握手载荷包含 X/Z")
      aw_q.push_back(a);
      aw_count++;
    end
    if (vif.mon_cb.s_axi_wvalid === 1'b1 &&
        vif.mon_cb.s_axi_wready === 1'b1) begin
      w = x2p_transaction::type_id::create("w");
      w.data = vif.mon_cb.s_axi_wdata;
      w.strb = vif.mon_cb.s_axi_wstrb;
      w.epoch = vif.mon_cb.epoch;
      w.accepted_cycle = cycle;
      if ($isunknown({w.data,w.strb}))
        `uvm_error("AXI_X", "W 握手载荷包含 X/Z")
      w_q.push_back(w);
      w_count++;
    end
    while (aw_q.size() && w_q.size()) begin
      a = aw_q.pop_front();
      w = w_q.pop_front();
      t = a.duplicate("write_request");
      t.cmd = X2P_WRITE; t.stage = X2P_REQUEST; t.write = 1;
      t.data = w.data; t.strb = w.strb;
      t.ordinal = wr_ordinal++;
      t.aw_w_order = (a.accepted_cycle < w.accepted_cycle) ? -1 :
                     (a.accepted_cycle > w.accepted_cycle) ? 1 : 0;
      t.accepted_cycle = (a.accepted_cycle > w.accepted_cycle) ?
                         a.accepted_cycle : w.accepted_cycle;
      wr_q.push_back(t.duplicate("pending_write"));
      req_put.put(t);
    end
    if (vif.mon_cb.s_axi_arvalid === 1'b1 &&
        vif.mon_cb.s_axi_arready === 1'b1) begin
      t = x2p_transaction::type_id::create("read_request");
      t.cmd = X2P_READ; t.stage = X2P_REQUEST; t.write = 0;
      t.addr = vif.mon_cb.s_axi_araddr;
      t.id = vif.mon_cb.s_axi_arid;
      t.size = vif.mon_cb.s_axi_arsize;
      t.prot = vif.mon_cb.s_axi_arprot;
      t.strb = 0; t.data = 0;
      t.epoch = vif.mon_cb.epoch;
      t.ordinal = rd_ordinal++;
      t.accepted_cycle = cycle;
      if ($isunknown({t.addr,t.id,t.size,t.prot}))
        `uvm_error("AXI_X", "AR 握手载荷包含 X/Z")
      rd_q.push_back(t.duplicate("pending_read"));
      req_put.put(t);
      ar_count++;
    end
  endtask

  task sample_responses();
    x2p_transaction t;
    if (vif.mon_cb.s_axi_bvalid === 1'b1 &&
        vif.mon_cb.s_axi_bready === 1'b0) b_stalls++;
    if (vif.mon_cb.s_axi_rvalid === 1'b1 &&
        vif.mon_cb.s_axi_rready === 1'b0) r_stalls++;
    if (vif.mon_cb.s_axi_bvalid === 1'b1 &&
        vif.mon_cb.s_axi_bready === 1'b1) begin
      if (!wr_q.size()) begin
        `uvm_error("EXTRA_B", "没有待处理写请求却出现 B 握手")
      end else begin
        t = wr_q.pop_front();
        t.stage = X2P_RESPONSE;
        t.id = vif.mon_cb.s_axi_bid;
        t.resp = vif.mon_cb.s_axi_bresp;
        t.data = 0;
        t.completed_cycle = cycle;
        t.stall_cycles = b_stalls;
        rsp_put.put(t);
      end
      b_count++;
      b_stalls = 0;
    end
    if (vif.mon_cb.s_axi_rvalid === 1'b1 &&
        vif.mon_cb.s_axi_rready === 1'b1) begin
      if (!rd_q.size()) begin
        `uvm_error("EXTRA_R", "没有待处理读请求却出现 R 握手")
      end else begin
        t = rd_q.pop_front();
        t.stage = X2P_RESPONSE;
        t.id = vif.mon_cb.s_axi_rid;
        t.resp = vif.mon_cb.s_axi_rresp;
        t.data = vif.mon_cb.s_axi_rdata;
        t.completed_cycle = cycle;
        t.stall_cycles = r_stalls;
        rsp_put.put(t);
      end
      r_count++;
      r_stalls = 0;
    end
  endtask

  task run_phase(uvm_phase phase);
    cycle = 0;
    forever begin
      @(vif.mon_cb);
      cycle++;
      if (vif.mon_cb.aresetn !== 1'b1) begin
        clear_pending();
      end else begin
        sample_requests();
        sample_responses();
        check_age();
      end
    end
  endtask
  function void report_phase(uvm_phase phase);
    `uvm_info("AXI_COUNTS",
      $sformatf("AW=%0d W=%0d AR=%0d B=%0d R=%0d aborted_partial=%0d aborted_requests=%0d",
      aw_count,w_count,ar_count,b_count,r_count,aborted_partial,aborted_requests), UVM_LOW)
  endfunction
endclass
