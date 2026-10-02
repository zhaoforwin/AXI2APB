`timescale 1ns/1ps
`default_nettype none

// Structural AXI5-Lite -> APB4 bridge. Existing interface names are preserved.
// Added AWID/AWSIZE/BID and ARID/ARSIZE/RID for IHI0022G C2.6.
// Compile this file together with axi4_lite_slave.v and apb_master.v.
module axilite2apb #(
    parameter integer ID_WIDTH = 4
) (
    input  wire        aclk,
    input  wire        aresetn,
    input  wire [31:0] s_axi_awaddr,
    input  wire [ID_WIDTH-1:0] s_axi_awid,
    input  wire [2:0]  s_axi_awsize,
    input  wire [2:0]  s_axi_awprot,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output wire [1:0]  s_axi_bresp,
    output wire [ID_WIDTH-1:0] s_axi_bid,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [31:0] s_axi_araddr,
    input  wire [ID_WIDTH-1:0] s_axi_arid,
    input  wire [2:0]  s_axi_arsize,
    input  wire [2:0]  s_axi_arprot,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output wire [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire [ID_WIDTH-1:0] s_axi_rid,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,
    output wire [31:0] m_apb_paddr,
    output wire [2:0]  m_apb_pprot,
    output wire        m_apb_psel,
    output wire        m_apb_penable,
    output wire        m_apb_pwrite,
    output wire [31:0] m_apb_pwdata,
    output wire [3:0]  m_apb_pstrb,
    input  wire [31:0] m_apb_prdata,
    input  wire        m_apb_pready,
    input  wire        m_apb_pslverr
);
    wire req_valid;
    wire req_ready;
    wire req_write;
    wire [31:0] req_addr;
    wire [2:0] req_prot;
    wire [31:0] req_wdata;
    wire [3:0] req_strb;
    wire rsp_valid;
    wire rsp_ready;
    wire [31:0] rsp_rdata;
    wire rsp_error;

    axi4_lite_slave #(
        .addr_width(32), .data_width(32), .strb_width(4), .id_width(ID_WIDTH)
    ) u_axi4_lite_slave (
        .aclk(aclk), .aresetn(aresetn),
        .awvalid(s_axi_awvalid), .awready(s_axi_awready),
        .awaddr(s_axi_awaddr), .awprot(s_axi_awprot),
        .awid(s_axi_awid), .awsize(s_axi_awsize), .bid(s_axi_bid),
        .wvalid(s_axi_wvalid), .wready(s_axi_wready),
        .wdata(s_axi_wdata), .wstrb(s_axi_wstrb),
        .bvalid(s_axi_bvalid), .bready(s_axi_bready), .bresp(s_axi_bresp),
        .arvalid(s_axi_arvalid), .arready(s_axi_arready),
        .araddr(s_axi_araddr), .arprot(s_axi_arprot),
        .arid(s_axi_arid), .arsize(s_axi_arsize), .rid(s_axi_rid),
        .rvalid(s_axi_rvalid), .rready(s_axi_rready),
        .rdata(s_axi_rdata), .rresp(s_axi_rresp),
        .req_valid(req_valid), .req_ready(req_ready),
        .req_write(req_write), .req_addr(req_addr), .req_prot(req_prot),
        .req_wdata(req_wdata), .req_strb(req_strb),
        .rsp_valid(rsp_valid), .rsp_ready(rsp_ready),
        .rsp_rdata(rsp_rdata), .rsp_error(rsp_error)
    );

    apb_master #(
        .addr_width(32), .data_width(32), .strb_width(4)
    ) u_apb_master (
        .clk(aclk), .rstn(aresetn),
        .req_valid(req_valid), .req_ready(req_ready),
        .req_write(req_write), .req_addr(req_addr), .req_prot(req_prot),
        .req_wdata(req_wdata), .req_strb(req_strb),
        .rsp_valid(rsp_valid), .rsp_ready(rsp_ready),
        .rsp_rdata(rsp_rdata), .rsp_error(rsp_error),
        .paddr(m_apb_paddr), .pprot(m_apb_pprot),
        .psel(m_apb_psel), .penable(m_apb_penable),
        .pwrite(m_apb_pwrite), .pwdata(m_apb_pwdata), .pstrb(m_apb_pstrb),
        .prdata(m_apb_prdata), .pready(m_apb_pready), .pslverr(m_apb_pslverr)
    );
endmodule
`default_nettype wire
