class x2p_apb_monitor extends uvm_monitor;
  `uvm_component_utils(x2p_apb_monitor)
  x2p_config cfg;
  x2p_vif_t vif;
  uvm_blocking_put_port #(x2p_transaction) done_put;
  protected bit active;
  protected int unsigned waited, programmed_wait;
  protected longint unsigned start_cycle;
  longint unsigned cycle;
  int unsigned completed_count, aborted_count;

  covergroup apb_cg with function sample(bit wr, int waits, bit err);
    option.per_instance = 1;
    cp_write: coverpoint wr;
    cp_wait: coverpoint waits {
      bins zero = {0}; bins one = {1}; bins three = {3}; bins eight = {8};
      bins seven = {7}; bins fifteen = {15}; bins thirty_one = {31};
      bins others = default;
    }
    cp_error: coverpoint err;
    rw_wait: cross cp_write, cp_wait;
    rw_error: cross cp_write, cp_error;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    apb_cg = new();
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(x2p_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NO_CFG", "APB monitor 缺少 cfg")
    vif = cfg.vif;
    done_put = new("done_put", this);
  endfunction
  function int pending_count();
    return int'(active);
  endfunction
  task run_phase(uvm_phase phase);
    x2p_transaction t;
    cycle = 0;
    forever begin
      @(vif.mon_cb);
      cycle++;
      if (vif.mon_cb.aresetn !== 1'b1) begin
        if (active) aborted_count++;
        active = 0; waited = 0;
      end else begin
        if (vif.mon_cb.m_apb_psel === 1'b1 &&
            vif.mon_cb.m_apb_penable === 1'b0) begin
          if (active) `uvm_error("APB_SETUP", "旧访问未完成，又出现 SETUP")
          active = 1; waited = 0; start_cycle = cycle;
          programmed_wait = cfg.apb_wait_cycles;
        end
        if (vif.mon_cb.m_apb_psel === 1'b1 &&
            vif.mon_cb.m_apb_penable === 1'b1) begin
          if (vif.mon_cb.m_apb_pready === 1'b1) begin
            if (!active) `uvm_error("APB_SETUP", "完成握手没有对应 SETUP")
            t = x2p_transaction::type_id::create("apb_done");
            t.stage = X2P_APB;
            t.write = vif.mon_cb.m_apb_pwrite;
            t.addr = vif.mon_cb.m_apb_paddr;
            t.prot = vif.mon_cb.m_apb_pprot;
            t.strb = vif.mon_cb.m_apb_pstrb;
            // data=写数据或读返回数据；APB没有 ID。
            t.data = t.write ? vif.mon_cb.m_apb_pwdata : vif.mon_cb.m_apb_prdata;
            t.error = vif.mon_cb.m_apb_pslverr;
            t.epoch = vif.mon_cb.epoch;
            t.wait_cycles = waited; t.programmed_wait = programmed_wait;
            t.completed_cycle = cycle;
            if ($isunknown({vif.mon_cb.m_apb_pwrite,t.addr,t.prot,t.strb,t.data,t.error}))
              `uvm_error("APB_X", "APB 完成握手载荷包含 X/Z")
            done_put.put(t);
            apb_cg.sample(t.write, t.wait_cycles, t.error);
            completed_count++;
            active = 0; waited = 0;
          end else begin
            waited++;
          end
        end
        if (active && cycle-start_cycle > cfg.item_timeout)
          `uvm_fatal("APB_TIMEOUT", "APB SETUP/ACCESS 超时")
      end
    end
  endtask
  function void report_phase(uvm_phase phase);
    `uvm_info("APB_COUNTS",
      $sformatf("completed=%0d aborted=%0d coverage=%.2f%%",
      completed_count,aborted_count,apb_cg.get_inst_coverage()), UVM_LOW)
  endfunction
endclass
