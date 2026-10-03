class x2p_axi_agent extends uvm_agent;
  `uvm_component_utils(x2p_axi_agent)
  x2p_axi_sequencer sqr;
  x2p_axi_driver dri;
  protected x2p_axi_monitor mon;
  uvm_blocking_put_port #(x2p_transaction) req_port, rsp_port;
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sqr = x2p_axi_sequencer::type_id::create("sqr", this);
    dri = x2p_axi_driver::type_id::create("dri", this);
    mon = x2p_axi_monitor::type_id::create("mon", this);
    req_port = new("req_port", this);
    rsp_port = new("rsp_port", this);
  endfunction
  function void connect_phase(uvm_phase phase);
    dri.seq_item_port.connect(sqr.seq_item_export);
    mon.req_put.connect(req_port);
    mon.rsp_put.connect(rsp_port);
  endfunction
  function int pending_count();
    return mon.pending_count();
  endfunction
endclass
