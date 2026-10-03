// 响应式从设备使用 component，避免创建一个不使用的 seq_item_port。
class x2p_apb_driver extends uvm_component;
  `uvm_component_utils(x2p_apb_driver)
  x2p_config cfg;
  x2p_vif_t vif;
  protected logic [31:0] regs[0:63];
  protected logic [31:0] latched_addr, latched_data, response_data;
  protected logic [3:0] latched_strb;
  protected bit active, latched_write;
  protected logic response_error;
  protected int unsigned wait_target, waited;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(x2p_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NO_CFG", "APB driver 缺少 cfg")
    vif = cfg.vif;
  endfunction
  function void reset_bank();
    foreach (regs[i]) regs[i] = 0;
    active = 0; waited = 0; wait_target = 0;
    response_data = 0; response_error = 0;
  endfunction

  // 从设备存储只在 APB 的完成握手提交写入。
  task observe_bus();
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.aresetn !== 1'b1) begin
        reset_bank();
      end else if (vif.mon_cb.m_apb_psel === 1'b1 &&
                   vif.mon_cb.m_apb_penable === 1'b0) begin
        active = 1;
        latched_addr = vif.mon_cb.m_apb_paddr;
        latched_data = vif.mon_cb.m_apb_pwdata;
        latched_strb = vif.mon_cb.m_apb_pstrb;
        latched_write = vif.mon_cb.m_apb_pwrite;
        waited = 0;
        wait_target = cfg.apb_wait_cycles;
        response_error = (latched_addr > 32'hfc) ||
                         (latched_addr[1:0] != 0) ||
                         (latched_write && latched_addr == 32'he0) ||
                         (!latched_write && latched_addr == 32'he4);
        if ($isunknown({latched_addr, vif.mon_cb.m_apb_pwrite})) begin
          `uvm_error("APB_X", "APB 请求包含未知地址或方向")
          response_error = 1;
        end
        if (latched_write) response_data = 0;
        else if (response_error) response_data = 32'hbad00bad;
        else response_data = regs[latched_addr[7:2]];
      end else if (vif.mon_cb.m_apb_psel === 1'b1 &&
                   vif.mon_cb.m_apb_penable === 1'b1 && active) begin
        if (vif.mon_cb.m_apb_pready === 1'b1) begin
          if (latched_write && !response_error)
            for (int i=0; i<4; i++)
              if (latched_strb[i])
                regs[latched_addr[7:2]][8*i +: 8] = latched_data[8*i +: 8];
          active = 0;
        end else begin
          waited++;
        end
      end
    end
  endtask

  task drive_response();
    forever begin
      @(vif.apb_drv_cb);
      if (vif.apb_drv_cb.aresetn !== 1'b1 || !active ||
          vif.apb_drv_cb.m_apb_psel !== 1'b1) begin
        vif.apb_drv_cb.m_apb_pready <= 0;
        vif.apb_drv_cb.m_apb_prdata <= 0;
        vif.apb_drv_cb.m_apb_pslverr <= 0;
      end else begin
        vif.apb_drv_cb.m_apb_prdata <= response_data;
        vif.apb_drv_cb.m_apb_pslverr <= response_error;
        vif.apb_drv_cb.m_apb_pready <=
           (vif.apb_drv_cb.m_apb_penable === 1'b1 && waited >= wait_target);
      end
    end
  endtask
  task run_phase(uvm_phase phase);
    reset_bank();
    // 响应式 driver 不从 sequencer 获取 item。
    fork
      observe_bus();
      drive_response();
    join
  endtask
endclass
