class x2p_axi_sequencer extends uvm_sequencer #(x2p_transaction);
  `uvm_component_utils(x2p_axi_sequencer)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass
