class x2p_test extends uvm_test;
  `uvm_component_utils(x2p_test)
  x2p_env env;
  x2p_config cfg;
  function new(string name, uvm_component parent);
    super.new(name,parent);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg=x2p_config::type_id::create("cfg");
    if (!uvm_config_db#(x2p_vif_t)::get(this,"","vif",cfg.vif))
      `uvm_fatal("NO_VIF","top 未绑定 x2p_interface")
    void'($value$plusargs("CASE=%d",cfg.case_select));
    if (cfg.case_select<0 || cfg.case_select>20)
      `uvm_fatal("BAD_CASE","CASE 必须为 0..20")
    uvm_config_db#(x2p_config)::set(this,"env*","cfg",cfg);
    env=x2p_env::type_id::create("env",this);
  endfunction
  function void end_of_elaboration_phase(uvm_phase phase);
    if ($test$plusargs("X2P_TOPOLOGY")) uvm_top.print_topology();
  endfunction
  task run_phase(uvm_phase phase);
    x2p_directed_sequence seq;
    bit drained;
    phase.raise_objection(this);
    seq=x2p_directed_sequence::type_id::create("seq");
    seq.cfg=cfg;
    seq.start(env.axi_age.sqr);
    // 留出 monitor/FIFO 消费线程处理最后一个握手，再检查积压。
    repeat (4) @(cfg.vif.mon_cb);
    drained=0;
    for (int i=0;i<cfg.item_timeout;i++) begin
      if (env.is_idle()) begin drained=1; break; end
      @(cfg.vif.mon_cb);
    end
    if (!drained) `uvm_error("DRAIN_TIMEOUT","sequence 结束后平台仍有积压")
    phase.drop_objection(this);
  endtask
  function void report_phase(uvm_phase phase);
    uvm_report_server server;
    server=uvm_report_server::get_server();
    if (server.get_severity_count(UVM_ERROR)==0 &&
        server.get_severity_count(UVM_FATAL)==0 &&
        env.scor.fail_count==0 && env.scor.pass_count>0)
      `uvm_info("X2P_RESULT","PASS (SVA failures also checked by check_log.py)",UVM_NONE)
    else
      `uvm_error("X2P_RESULT","FAIL")
  endfunction
endclass
