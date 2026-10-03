class x2p_refmodel extends uvm_component;
  `uvm_component_utils(x2p_refmodel)
  x2p_config cfg;
  x2p_vif_t vif;
  uvm_blocking_get_port #(x2p_transaction) axi_req_get, apb_done_get;
  uvm_blocking_put_port #(x2p_transaction) exp_port;
  protected x2p_transaction wr_q[$], rd_q[$], apb_q[$];
  protected logic [31:0] ref_regs[0:63];
  protected semaphore pump_lock;
  int unsigned request_count, apb_count, predicted_count, normal_predicted;
  int unsigned local_predicted, aborted_pending, aborted_apb, stale_count;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    pump_lock = new(1);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(x2p_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NO_CFG", "reference model 缺少 cfg")
    vif = cfg.vif;
    axi_req_get = new("axi_req_get", this);
    apb_done_get = new("apb_done_get", this);
    exp_port = new("exp_port", this);
  endfunction
  function void reset_state();
    aborted_pending += wr_q.size()+rd_q.size();
    aborted_apb += apb_q.size();
    wr_q.delete(); rd_q.delete(); apb_q.delete();
    foreach (ref_regs[i]) ref_regs[i] = 0;
  endfunction
  function bit is_idle();
    return wr_q.size()==0 && rd_q.size()==0 && apb_q.size()==0;
  endfunction

  // 规则以原始 AXI 请求为输入，不使用 DUT 的 PSLVERR 作答案。
  function bit expected_error(logic [31:0] aligned_addr, bit wr);
    return (aligned_addr > 32'hfc) ||
           (wr && aligned_addr == 32'he0) ||
           (!wr && aligned_addr == 32'he4);
  endfunction

  task emit_local(x2p_transaction r);
    x2p_transaction e;
    e = r.duplicate("local_expected");
    e.stage = X2P_RESPONSE;
    e.resp = 2'b10; e.error = 1; e.data = 0; e.apb_cycle = 0;
    exp_port.put(e);
    predicted_count++; local_predicted++;
  endtask

  task predict_completed(x2p_transaction r, x2p_transaction a);
    x2p_transaction e;
    logic [31:0] aligned_addr, expected_data;
    bit err;
    aligned_addr = {r.addr[31:2],2'b00};
    err = expected_error(aligned_addr, r.write);
    if (a.addr !== aligned_addr || a.write !== r.write ||
        a.prot !== r.prot ||
        (r.write && (a.data !== r.data || a.strb !== r.strb)) ||
        (!r.write && a.strb !== 4'b0000))
      `uvm_error("APB_MAP",
        $sformatf("epoch=%0d %s #%0d AXI addr=%08h prot=%h data=%08h strb=%h -> APB addr=%08h prot=%h data=%08h strb=%h",
        r.epoch,r.write?"W":"R",r.ordinal,r.addr,r.prot,r.data,r.strb,
        a.addr,a.prot,a.data,a.strb))
    if (a.error !== err)
      `uvm_error("APB_ERROR",
        $sformatf("地址 %08h 方向 %s: PSLVERR exp=%b act=%b",
                  aligned_addr,r.write?"W":"R",err,a.error))
    if (a.wait_cycles != a.programmed_wait)
      `uvm_error("APB_WAIT",
        $sformatf("ACCESS wait exp=%0d act=%0d",a.programmed_wait,a.wait_cycles))
    if (a.completed_cycle < r.accepted_cycle)
      `uvm_error("APB_EARLY", "APB 完成早于 AXI 请求接收")

    expected_data = 0;
    if (r.write) begin
      if (!err)
        for (int i=0; i<4; i++)
          if (r.strb[i])
            ref_regs[aligned_addr[7:2]][8*i +: 8] = r.data[8*i +: 8];
    end else begin
      expected_data = err ? 32'hbad00bad : ref_regs[aligned_addr[7:2]];
      if (a.data !== expected_data)
        `uvm_error("APB_RDATA",
          $sformatf("地址 %08h: PRDATA exp=%08h act=%08h",
                    aligned_addr,expected_data,a.data))
    end
    e = r.duplicate("apb_expected");
    e.stage = X2P_RESPONSE;
    e.resp = err ? 2'b10 : 2'b00;
    e.error = err; e.data = expected_data;
    e.apb_cycle = a.completed_cycle;
    exp_port.put(e);
    predicted_count++; normal_predicted++;
  endtask

  // 两个接收线程分别缓存。APB 先到但 AXI 接收线程尚未运行时，保留事件。
  // 只按方向取请求；寄存器状态按实际 APB 完成顺序更新。
  task pump();
    x2p_transaction r, a;
    while (wr_q.size() && wr_q[0].size > 2) begin
      r = wr_q.pop_front();
      emit_local(r);
    end
    while (rd_q.size() && rd_q[0].size > 2) begin
      r = rd_q.pop_front();
      emit_local(r);
    end
    while (apb_q.size()) begin
      a = apb_q[0];
      if (a.write) begin
        if (!wr_q.size()) break;
        r = wr_q.pop_front();
      end else begin
        if (!rd_q.size()) break;
        r = rd_q.pop_front();
      end
      a = apb_q.pop_front();
      predict_completed(r,a);
    end
  endtask
  task receive_axi();
    x2p_transaction t;
    forever begin
      axi_req_get.get(t);
      pump_lock.get(1);
      if (t.epoch != vif.epoch || vif.aresetn !== 1'b1) stale_count++;
      else begin
        if (t.write) wr_q.push_back(t);
        else rd_q.push_back(t);
        request_count++;
        pump();
      end
      pump_lock.put(1);
    end
  endtask
  task receive_apb();
    x2p_transaction t;
    forever begin
      apb_done_get.get(t);
      pump_lock.get(1);
      if (t.epoch != vif.epoch || vif.aresetn !== 1'b1) stale_count++;
      else begin
        apb_q.push_back(t);
        apb_count++;
        pump();
      end
      pump_lock.put(1);
    end
  endtask
  task run_phase(uvm_phase phase);
    fork
      receive_axi();
      receive_apb();
    join
  endtask
  function void check_phase(uvm_phase phase);
    if (!is_idle())
      `uvm_error("REF_PENDING",
        $sformatf("未处理 W=%0d R=%0d APB=%0d",wr_q.size(),rd_q.size(),apb_q.size()))
    if (request_count != predicted_count+aborted_pending)
      `uvm_error("REF_COUNT", "AXI 请求数量与预测/复位取消数量不一致")
    if (apb_count != normal_predicted+aborted_apb)
      `uvm_error("APB_COUNT", "APB 完成数量与正常预测/取消数量不一致")
  endfunction
  function void report_phase(uvm_phase phase);
    `uvm_info("REF_COUNTS",
      $sformatf("requests=%0d APB=%0d expected=%0d local_SIZE=%0d aborted_pending=%0d stale=%0d",
      request_count,apb_count,predicted_count,local_predicted,aborted_pending,stale_count), UVM_LOW)
  endfunction
endclass
