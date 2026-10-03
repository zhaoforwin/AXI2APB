class x2p_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(x2p_scoreboard)
  x2p_config cfg;
  x2p_vif_t vif;
  uvm_blocking_get_port #(x2p_transaction) exp_get, act_get;
  protected x2p_transaction exp_w[$], exp_r[$], act_w[$], act_r[$];
  protected semaphore compare_lock;
  int unsigned expected_count, actual_count, compared_count, pass_count, fail_count;
  int unsigned aborted_expected, aborted_actual, stale_count;

  covergroup axi_cg with function sample(bit wr, logic [31:0] addr,
                   int sz, int strb, int response, int id, int order, int stalls, int prot);
    option.per_instance = 1;
    cp_write: coverpoint wr;
    cp_addr: coverpoint addr {
      bins first = {0}; bins last = {32'hfc};
      bins registers = {[1:32'hfb]};
      bins invalid = {[32'h100:32'hffffffff]};
    }
    cp_size: coverpoint sz {
      bins byte_access = {0}; bins halfword = {1}; bins word_access = {2};
      bins rejected[] = {[3:7]};
    }
    cp_strb: coverpoint strb iff (wr) { bins masks[] = {[0:15]}; }
    cp_resp: coverpoint response { bins okay = {0}; bins slverr = {2}; }
    cp_id: coverpoint id { bins ids[] = {[0:(1<<`X2P_ID_WIDTH)-1]}; }
    cp_prot: coverpoint prot { bins secure = {0}; bins nonsecure = {2}; }
    cp_order: coverpoint order iff (wr) {
      bins aw_first = {-1}; bins together = {0}; bins w_first = {1};
    }
    cp_stalls: coverpoint stalls {
      bins zero = {0}; bins three = {3}; bins eight = {8}; bins others = default;
    }
    rw_resp: cross cp_write, cp_resp;
    rw_size: cross cp_write, cp_size;
    rw_stalls: cross cp_write, cp_stalls;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    compare_lock = new(1);
    axi_cg = new();
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(x2p_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NO_CFG", "scoreboard 缺少 cfg")
    vif = cfg.vif;
    exp_get = new("exp_get", this);
    act_get = new("act_get", this);
  endfunction
  function void reset_state();
    aborted_expected += exp_w.size()+exp_r.size();
    aborted_actual += act_w.size()+act_r.size();
    exp_w.delete(); exp_r.delete(); act_w.delete(); act_r.delete();
  endfunction
  function bit is_idle();
    return exp_w.size()==0 && exp_r.size()==0 && act_w.size()==0 && act_r.size()==0;
  endfunction
  function void compare_one(x2p_transaction e, x2p_transaction a);
    bit good;
    good = (e.epoch == a.epoch) && (e.ordinal == a.ordinal) &&
           (e.write === a.write) && (e.id === a.id) &&
           (e.resp === a.resp) && (e.write || e.data === a.data);
    if (e.apb_cycle != 0 && a.completed_cycle <= e.apb_cycle) good = 0;
    if (a.completed_cycle < e.accepted_cycle) good = 0;
    compared_count++;
    if (good) begin
      pass_count++;
      axi_cg.sample(a.write,{a.addr[31:2],2'b00},a.size,a.strb,
                    a.resp,a.id,a.aw_w_order,a.stall_cycles,a.prot);
      `uvm_info("SCOR_PASS",
        $sformatf("epoch=%0d %s #%0d addr=%08h ID=%h RESP=%b DATA=%08h",
          e.epoch,e.write?"W":"R",e.ordinal,e.addr,a.id,a.resp,a.data), UVM_MEDIUM)
    end else begin
      fail_count++;
      `uvm_error("SCOR_FAIL",
        $sformatf("epoch=%0d %s #%0d addr=%08h exp(ID=%h RESP=%b DATA=%08h) act(epoch=%0d #%0d ID=%h RESP=%b DATA=%08h) APBcycle=%0d AXIcycle=%0d",
          e.epoch,e.write?"W":"R",e.ordinal,e.addr,e.id,e.resp,e.data,
          a.epoch,a.ordinal,a.id,a.resp,a.data,e.apb_cycle,a.completed_cycle))
    end
  endfunction
  function void compare_available();
    x2p_transaction e,a;
    while (exp_w.size() && act_w.size()) begin
      e=exp_w.pop_front(); a=act_w.pop_front(); compare_one(e,a);
    end
    while (exp_r.size() && act_r.size()) begin
      e=exp_r.pop_front(); a=act_r.pop_front(); compare_one(e,a);
    end
  endfunction
  task receive_expected();
    x2p_transaction t;
    forever begin
      exp_get.get(t);
      compare_lock.get(1);
      if (t.epoch != vif.epoch || vif.aresetn !== 1'b1) stale_count++;
      else begin
        if (t.write) exp_w.push_back(t); else exp_r.push_back(t);
        expected_count++;
        compare_available();
      end
      compare_lock.put(1);
    end
  endtask
  task receive_actual();
    x2p_transaction t;
    forever begin
      act_get.get(t);
      compare_lock.get(1);
      if (t.epoch != vif.epoch || vif.aresetn !== 1'b1) stale_count++;
      else begin
        if (t.write) act_w.push_back(t); else act_r.push_back(t);
        actual_count++;
        compare_available();
      end
      compare_lock.put(1);
    end
  endtask
  task run_phase(uvm_phase phase);
    fork
      receive_expected();
      receive_actual();
    join
  endtask
  function void check_phase(uvm_phase phase);
    if (!is_idle())
      `uvm_error("SCOR_PENDING",
        $sformatf("expW=%0d expR=%0d actW=%0d actR=%0d",
          exp_w.size(),exp_r.size(),act_w.size(),act_r.size()))
    if (expected_count != compared_count+aborted_expected ||
        actual_count != compared_count+aborted_actual)
      `uvm_error("SCOR_COUNT", "响应数量与比较/取消数量不一致")
  endfunction
  function void report_phase(uvm_phase phase);
    `uvm_info("SCOR_SUMMARY",
      $sformatf("PASS=%0d FAIL=%0d expected=%0d actual=%0d aborted_exp=%0d aborted_act=%0d coverage=%.2f%%",
      pass_count,fail_count,expected_count,actual_count,aborted_expected,
      aborted_actual,axi_cg.get_inst_coverage()), UVM_LOW)
  endfunction
endclass
