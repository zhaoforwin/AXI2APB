`timescale 1ns/1ps
`include "x2p_defs.svh"

interface x2p_interface #(parameter int ID_WIDTH = `X2P_ID_WIDTH)
                        (input logic aclk);
  logic aresetn = 0;
  int unsigned epoch = 0;
  logic [31:0] s_axi_awaddr = 0;
  logic [ID_WIDTH-1:0] s_axi_awid = 0;
  logic [2:0] s_axi_awsize = 2, s_axi_awprot = 0;
  logic s_axi_awvalid = 0, s_axi_awready;
  logic [31:0] s_axi_wdata = 0;
  logic [3:0] s_axi_wstrb = 0;
  logic s_axi_wvalid = 0, s_axi_wready;
  logic [1:0] s_axi_bresp;
  logic [ID_WIDTH-1:0] s_axi_bid;
  logic s_axi_bvalid, s_axi_bready = 0;
  logic [31:0] s_axi_araddr = 0;
  logic [ID_WIDTH-1:0] s_axi_arid = 0;
  logic [2:0] s_axi_arsize = 2, s_axi_arprot = 0;
  logic s_axi_arvalid = 0, s_axi_arready;
  logic [31:0] s_axi_rdata;
  logic [1:0] s_axi_rresp;
  logic [ID_WIDTH-1:0] s_axi_rid;
  logic s_axi_rvalid, s_axi_rready = 0;
  logic [31:0] m_apb_paddr;
  logic [2:0] m_apb_pprot;
  logic m_apb_psel, m_apb_penable, m_apb_pwrite;
  logic [31:0] m_apb_pwdata;
  logic [3:0] m_apb_pstrb;
  logic [31:0] m_apb_prdata = 0;
  logic m_apb_pready = 0, m_apb_pslverr = 0;

  // 握手只用上升沿前的采样值，避开 DUT 的 NBA 更新。
  clocking mon_cb @(posedge aclk);
    default input #1step;
    input aresetn, epoch;
    input s_axi_awaddr, s_axi_awid, s_axi_awsize, s_axi_awprot;
    input s_axi_awvalid, s_axi_awready, s_axi_wdata, s_axi_wstrb;
    input s_axi_wvalid, s_axi_wready, s_axi_bresp, s_axi_bid;
    input s_axi_bvalid, s_axi_bready;
    input s_axi_araddr, s_axi_arid, s_axi_arsize, s_axi_arprot;
    input s_axi_arvalid, s_axi_arready, s_axi_rdata, s_axi_rresp;
    input s_axi_rid, s_axi_rvalid, s_axi_rready;
    input m_apb_paddr, m_apb_pprot, m_apb_psel, m_apb_penable;
    input m_apb_pwrite, m_apb_pwdata, m_apb_pstrb;
    input m_apb_prdata, m_apb_pready, m_apb_pslverr;
  endclocking

  // AXI driver 是 AXI 主机信号及复位的唯一驱动者。
  clocking axi_drv_cb @(negedge aclk);
    default input #1step output #0;
    output aresetn;
    output s_axi_awaddr, s_axi_awid, s_axi_awsize, s_axi_awprot;
    output s_axi_awvalid, s_axi_wdata, s_axi_wstrb, s_axi_wvalid;
    output s_axi_bready;
    output s_axi_araddr, s_axi_arid, s_axi_arsize, s_axi_arprot;
    output s_axi_arvalid, s_axi_rready;
    input m_apb_psel, m_apb_penable, m_apb_pready;
    input s_axi_bvalid, s_axi_rvalid;
  endclocking

  // APB driver 只驱动从设备响应，地址与控制来自 DUT。
  clocking apb_drv_cb @(negedge aclk);
    default input #1step output #0;
    input aresetn, m_apb_psel, m_apb_penable;
    output m_apb_prdata, m_apb_pready, m_apb_pslverr;
  endclocking
endinterface
