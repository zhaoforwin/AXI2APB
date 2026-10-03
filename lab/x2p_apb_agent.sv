class x2p_apb_agent extends uvm_agent;
  `uvm_component_utils(x2p_apb_agent)
  x2p_apb_driver dri;
  protected x2p_apb_monitor mon;
  uvm_blocking_put_port #(x2p_transaction) done_port;
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    dri = x2p_apb_driver::type_id::create("dri", this);
    mon = x2p_apb_monitor::type_id::create("mon", this);
    done_port = new("done_port", this);
  endfunction
  function void connect_phase(uvm_phase phase);
    mon.done_put.connect(done_port);
  endfunction
  function int pending_count();
    return mon.pending_count();
  endfunction
endclass
