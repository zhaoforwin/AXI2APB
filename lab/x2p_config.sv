typedef virtual x2p_interface #(`X2P_ID_WIDTH) x2p_vif_t;
typedef enum {X2P_WRITE, X2P_READ, X2P_RW, X2P_RESET} x2p_cmd_e;
typedef enum {X2P_REQUEST, X2P_RESPONSE, X2P_APB} x2p_stage_e;
typedef enum {X2P_NO_ABORT, X2P_AFTER_AW, X2P_AFTER_W,
              X2P_AT_SETUP, X2P_AT_WAIT, X2P_AT_B_STALL,
              X2P_AT_R_STALL} x2p_abort_e;

class x2p_config extends uvm_object;
  `uvm_object_utils(x2p_config)
  x2p_vif_t vif;
  int unsigned apb_wait_cycles = 0;
  int unsigned item_timeout = 100;
  int unsigned reset_cycles = 4;
  int case_select = 0;  // 0=全部；1..20=单独一组。
  function new(string name="x2p_config");
    super.new(name);
  endfunction
endclass
