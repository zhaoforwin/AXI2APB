class x2p_env extends uvm_env;
  `uvm_component_utils(x2p_env)
  x2p_config cfg;
  x2p_vif_t vif;
  x2p_axi_agent axi_age;
  x2p_apb_agent apb_age;
  x2p_refmodel refm;
  x2p_scoreboard scor;
  uvm_tlm_fifo #(x2p_transaction) axi_req_fifo, apb_done_fifo, exp_fifo, act_fifo;
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(x2p_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NO_CFG", "env 缺少 cfg")
    vif=cfg.vif;
    axi_age=x2p_axi_agent::type_id::create("axi_age",this);
    apb_age=x2p_apb_agent::type_id::create("apb_age",this);
    refm=x2p_refmodel::type_id::create("refm",this);
    scor=x2p_scoreboard::type_id::create("scor",this);
    // size=0 表示无容量上限，monitor 的 put 不因 FIFO 满而漏采。
    axi_req_fifo=new("axi_req_fifo",this,0);
    apb_done_fifo=new("apb_done_fifo",this,0);
    exp_fifo=new("exp_fifo",this,0);
    act_fifo=new("act_fifo",this,0);
  endfunction
  function void connect_phase(uvm_phase phase);
    // env 只访问 agent 公开端口，不访问 monitor 内部。
    axi_age.req_port.connect(axi_req_fifo.put_export);
    refm.axi_req_get.connect(axi_req_fifo.get_peek_export);
    apb_age.done_port.connect(apb_done_fifo.put_export);
    refm.apb_done_get.connect(apb_done_fifo.get_peek_export);
    refm.exp_port.connect(exp_fifo.put_export);
    scor.exp_get.connect(exp_fifo.get_peek_export);
    axi_age.rsp_port.connect(act_fifo.put_export);
    scor.act_get.connect(act_fifo.get_peek_export);
  endfunction
  function void reset_state();
    axi_req_fifo.flush(); apb_done_fifo.flush();
    exp_fifo.flush(); act_fifo.flush();
    refm.reset_state(); scor.reset_state();
  endfunction
  function bit is_idle();
    return axi_req_fifo.used()==0 && apb_done_fifo.used()==0 &&
           exp_fifo.used()==0 && act_fifo.used()==0 &&
           refm.is_idle() && scor.is_idle() &&
           axi_age.pending_count()==0 && apb_age.pending_count()==0 &&
           vif.s_axi_bvalid===1'b0 && vif.s_axi_rvalid===1'b0 &&
           vif.m_apb_psel===1'b0;
  endfunction
  task run_phase(uvm_phase phase);
    reset_state();
    forever begin
      @(negedge vif.aresetn);
      reset_state();
    end
  endtask
  function void check_phase(uvm_phase phase);
    if (!is_idle()) `uvm_error("ENV_PENDING", "结束时平台仍有未完成事务")
  endfunction
endclass
