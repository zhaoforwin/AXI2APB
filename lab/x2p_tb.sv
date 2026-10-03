`timescale 1ns/1ps
`include "x2p_defs.svh"
module x2p_tb;
  import uvm_pkg::*;
  import x2p_pkg::*;
  localparam int ID_WIDTH=`X2P_ID_WIDTH;
  localparam time CLK_PERIOD=20ns;
  logic aclk=0;
  always #(CLK_PERIOD/2) aclk=~aclk;
  x2p_interface #(.ID_WIDTH(ID_WIDTH)) intf(.aclk(aclk));
  axilite2apb #(.ID_WIDTH(ID_WIDTH)) dut (
    .aclk(aclk), .aresetn(intf.aresetn),
    .s_axi_awaddr(intf.s_axi_awaddr), .s_axi_awid(intf.s_axi_awid),
    .s_axi_awsize(intf.s_axi_awsize), .s_axi_awprot(intf.s_axi_awprot),
    .s_axi_awvalid(intf.s_axi_awvalid), .s_axi_awready(intf.s_axi_awready),
    .s_axi_wdata(intf.s_axi_wdata), .s_axi_wstrb(intf.s_axi_wstrb),
    .s_axi_wvalid(intf.s_axi_wvalid), .s_axi_wready(intf.s_axi_wready),
    .s_axi_bresp(intf.s_axi_bresp), .s_axi_bid(intf.s_axi_bid),
    .s_axi_bvalid(intf.s_axi_bvalid), .s_axi_bready(intf.s_axi_bready),
    .s_axi_araddr(intf.s_axi_araddr), .s_axi_arid(intf.s_axi_arid),
    .s_axi_arsize(intf.s_axi_arsize), .s_axi_arprot(intf.s_axi_arprot),
    .s_axi_arvalid(intf.s_axi_arvalid), .s_axi_arready(intf.s_axi_arready),
    .s_axi_rdata(intf.s_axi_rdata), .s_axi_rresp(intf.s_axi_rresp),
    .s_axi_rid(intf.s_axi_rid), .s_axi_rvalid(intf.s_axi_rvalid),
    .s_axi_rready(intf.s_axi_rready),
    .m_apb_paddr(intf.m_apb_paddr), .m_apb_pprot(intf.m_apb_pprot),
    .m_apb_psel(intf.m_apb_psel), .m_apb_penable(intf.m_apb_penable),
    .m_apb_pwrite(intf.m_apb_pwrite), .m_apb_pwdata(intf.m_apb_pwdata),
    .m_apb_pstrb(intf.m_apb_pstrb), .m_apb_prdata(intf.m_apb_prdata),
    .m_apb_pready(intf.m_apb_pready), .m_apb_pslverr(intf.m_apb_pslverr)
  );
  initial begin
    uvm_config_db#(x2p_vif_t)::set(null,"uvm_test_top","vif",intf);
    run_test("x2p_test");
  end
  initial begin
    if ($test$plusargs("X2P_DUMP_VCD")) begin
      $dumpfile("x2p.vcd");
      $dumpvars(0,x2p_tb);
    end
  end
`ifdef X2P_FSDB
  initial begin
    $fsdbDumpfile("x2p.fsdb");
    $fsdbDumpvars(0,x2p_tb);
    $fsdbDumpMDA();
  end
`endif
  initial begin
    #1ms;
    $fatal(1,"X2P_GLOBAL_TIMEOUT: simulation exceeded 1 ms");
  end
endmodule
