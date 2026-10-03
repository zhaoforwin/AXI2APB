class x2p_transaction extends uvm_sequence_item;
  x2p_cmd_e cmd = X2P_WRITE;
  x2p_stage_e stage = X2P_REQUEST;
  x2p_abort_e abort_at = X2P_NO_ABORT;
  string label;
  bit write;
  logic [31:0] addr, data;
  logic [`X2P_ID_WIDTH-1:0] id;
  logic [2:0] size = 2, prot = 0;
  logic [3:0] strb = 4'hf;
  logic [1:0] resp;
  logic error;
  // X2P_RW 的读通道；写通道仍使用 addr/data/id 等公共字段。
  logic [31:0] rd_addr;
  logic [`X2P_ID_WIDTH-1:0] rd_id;
  logic [2:0] rd_size = 2, rd_prot = 0;
  int unsigned aw_delay = 0, w_delay = 0, ar_delay = 0;
  int unsigned b_delay = 0, r_delay = 0;
  int unsigned apb_wait_cycles = 0;
  int unsigned epoch, ordinal;
  int unsigned wait_cycles, programmed_wait, stall_cycles;
  int aw_w_order; // -1=AW先，0=同拍，1=W先。
  longint unsigned accepted_cycle, completed_cycle, apb_cycle;
  bit aborted;

  `uvm_object_utils_begin(x2p_transaction)
    `uvm_field_enum(x2p_cmd_e, cmd, UVM_ALL_ON)
    `uvm_field_enum(x2p_stage_e, stage, UVM_ALL_ON)
    `uvm_field_enum(x2p_abort_e, abort_at, UVM_ALL_ON)
    `uvm_field_string(label, UVM_ALL_ON)
    `uvm_field_int(write, UVM_ALL_ON)
    `uvm_field_int(addr, UVM_ALL_ON)
    `uvm_field_int(data, UVM_ALL_ON)
    `uvm_field_int(id, UVM_ALL_ON)
    `uvm_field_int(size, UVM_ALL_ON)
    `uvm_field_int(prot, UVM_ALL_ON)
    `uvm_field_int(strb, UVM_ALL_ON)
    `uvm_field_int(resp, UVM_ALL_ON)
    `uvm_field_int(error, UVM_ALL_ON)
    `uvm_field_int(rd_addr, UVM_ALL_ON)
    `uvm_field_int(rd_id, UVM_ALL_ON)
    `uvm_field_int(rd_size, UVM_ALL_ON)
    `uvm_field_int(rd_prot, UVM_ALL_ON)
    `uvm_field_int(aw_delay, UVM_ALL_ON)
    `uvm_field_int(w_delay, UVM_ALL_ON)
    `uvm_field_int(ar_delay, UVM_ALL_ON)
    `uvm_field_int(b_delay, UVM_ALL_ON)
    `uvm_field_int(r_delay, UVM_ALL_ON)
    `uvm_field_int(apb_wait_cycles, UVM_ALL_ON)
    `uvm_field_int(epoch, UVM_ALL_ON)
    `uvm_field_int(ordinal, UVM_ALL_ON)
    `uvm_field_int(wait_cycles, UVM_ALL_ON)
    `uvm_field_int(programmed_wait, UVM_ALL_ON)
    `uvm_field_int(stall_cycles, UVM_ALL_ON)
    `uvm_field_int(aw_w_order, UVM_ALL_ON)
    `uvm_field_int(accepted_cycle, UVM_ALL_ON)
    `uvm_field_int(completed_cycle, UVM_ALL_ON)
    `uvm_field_int(apb_cycle, UVM_ALL_ON)
    `uvm_field_int(aborted, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name="x2p_transaction");
    super.new(name);
  endfunction
  function x2p_transaction duplicate(string name="copy");
    x2p_transaction t;
    t = x2p_transaction::type_id::create(name);
    t.copy(this);
    return t;
  endfunction
endclass
