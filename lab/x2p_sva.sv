`timescale 1ns/1ps
`default_nettype none

// Ten DUT assertions for the three supplied bridge modules.
// S01 and S09-S10 include implementation-specific requirements.
// Compile once with the RTL. No UVM dependency and no RTL edits required.
module x2p_sva #(
    parameter integer ID_WIDTH = 4
) (
    input wire aclk, aresetn,
    input wire awready, wready, arready,
    input wire bvalid, bready,
    input wire [1:0] bresp,
    input wire [ID_WIDTH-1:0] bid,
    input wire rvalid, rready,
    input wire [31:0] rdata,
    input wire [1:0] rresp,
    input wire [ID_WIDTH-1:0] rid,
    input wire psel, penable, pwrite, pready, pslverr,
    input wire [31:0] paddr, pwdata, prdata,
    input wire [2:0] pprot,
    input wire [3:0] pstrb,
    input wire req_valid, req_write,
    input wire rsp_valid, rsp_ready, rsp_error,
    input wire [31:0] rsp_rdata,
    input wire [ID_WIDTH-1:0] awid_saved, arid_saved
);
    default clocking cb @(posedge aclk); endclocking

    // S01: no disable iff here; check after reset was sampled low previously.
    S01_reset_quiet: assert property (
        (!aresetn && ($past(aresetn) === 1'b0)) |->
        (!awready && !wready && !arready &&
         !bvalid && !rvalid && !psel && !penable &&
         !req_valid && !rsp_valid)
    ) else $error("X2P_SVA S01 reset outputs are not quiet");

    // S02: PENABLE may be asserted only while this APB port is selected.
    S02_enable_selected: assert property (
        disable iff (!aresetn) penable |-> psel
    ) else $error("X2P_SVA S02 PENABLE without PSEL");

    // S03: SETUP lasts one clock; master-owned payload is retained.
    S03_setup_to_access: assert property (
        disable iff (!aresetn)
        (psel && !penable) |=>
        (psel && penable &&
         $stable({paddr, pprot, pwrite, pstrb}) &&
         (!$past(pwrite) || $stable(pwdata)))
    ) else $error("X2P_SVA S03 SETUP to ACCESS violation");

    // S04: stability includes the final ACCESS edge where PREADY goes high.
    S04_wait_hold: assert property (
        disable iff (!aresetn)
        (psel && penable && !pready) |=>
        (psel && penable &&
         $stable({paddr, pprot, pwrite, pstrb}) &&
         (!$past(pwrite) || $stable(pwdata)))
    ) else $error("X2P_SVA S04 request changed during APB wait");

    // S05: a completed ACCESS must be followed by IDLE or SETUP.
    S05_access_exit: assert property (
        disable iff (!aresetn)
        (psel && penable && pready) |=> !penable
    ) else $error("X2P_SVA S05 completed ACCESS repeated");

    // S06: APB read transfers must not assert write strobes.
    S06_read_strobes: assert property (
        disable iff (!aresetn)
        (psel && !pwrite) |-> (pstrb == 4'b0000)
    ) else $error("X2P_SVA S06 nonzero read PSTRB");

    // S07-S08: VALID and payload remain stable through a stalled response.
    S07_b_stall_hold: assert property (
        disable iff (!aresetn)
        (bvalid && !bready) |=> (bvalid && $stable({bresp, bid}))
    ) else $error("X2P_SVA S07 write response changed while stalled");

    S08_r_stall_hold: assert property (
        disable iff (!aresetn)
        (rvalid && !rready) |=>
        (rvalid && $stable({rdata, rresp, rid}))
    ) else $error("X2P_SVA S08 read response changed while stalled");

    // S09: the backend registers only the final APB data and error sample.
    S09_apb_capture: assert property (
        disable iff (!aresetn)
        (psel && penable && pready) |=>
        (rsp_valid && (rsp_error == $past(pslverr)) &&
         (rsp_rdata == ($past(pwrite) ? 32'b0 : $past(prdata))))
    ) else $error("X2P_SVA S09 APB completion capture mismatch");

    // S10: the frontend registers an AXI response on the next sample.
    // Local oversized-SIZE rejections do not pass through this antecedent.
    S10_axi_response_map: assert property (
        disable iff (!aresetn)
        (rsp_valid && rsp_ready) |=>
        ($past(req_write) ?
          (bvalid && (bresp == ($past(rsp_error) ? 2'b10 : 2'b00)) &&
           (bid == $past(awid_saved))) :
          (rvalid && (rresp == ($past(rsp_error) ? 2'b10 : 2'b00)) &&
           (rdata == $past(rsp_rdata)) && (rid == $past(arid_saved))))
    ) else $error("X2P_SVA S10 AXI response mapping mismatch");

    // Covers record that the intended situations occurred, not just vacuity.
    C01_reset: cover property (!aresetn ##1 !aresetn);
    C02_enable: cover property (disable iff (!aresetn) penable);
    C03_setup: cover property (disable iff (!aresetn)
        (psel && !penable) ##1 (psel && penable));
    C04_wait: cover property (disable iff (!aresetn)
        (psel && penable && !pready)[*2] ##1 (psel && penable && pready));
    C05_complete: cover property (disable iff (!aresetn)
        (psel && penable && pready) ##1 !penable);
    C06_read: cover property (disable iff (!aresetn) (psel && !pwrite));
    C07_b_stall: cover property (disable iff (!aresetn)
        (bvalid && !bready)[*2] ##1 (bvalid && bready));
    C08_r_stall: cover property (disable iff (!aresetn)
        (rvalid && !rready)[*2] ##1 (rvalid && rready));
    C09_capture: cover property (disable iff (!aresetn)
        (psel && penable && pready) ##1 rsp_valid);
    C10_response: cover property (disable iff (!aresetn)
        (rsp_valid && rsp_ready) ##1 (bvalid || rvalid));
endmodule

// The target type, parameter and instance names match the supplied RTL.
bind axilite2apb x2p_sva #(.ID_WIDTH(ID_WIDTH)) u_x2p_sva (
    .aclk(aclk), .aresetn(aresetn),
    .awready(s_axi_awready), .wready(s_axi_wready),
    .arready(s_axi_arready),
    .bvalid(s_axi_bvalid), .bready(s_axi_bready),
    .bresp(s_axi_bresp), .bid(s_axi_bid),
    .rvalid(s_axi_rvalid), .rready(s_axi_rready),
    .rdata(s_axi_rdata), .rresp(s_axi_rresp), .rid(s_axi_rid),
    .psel(m_apb_psel), .penable(m_apb_penable),
    .pwrite(m_apb_pwrite), .pready(m_apb_pready),
    .pslverr(m_apb_pslverr),
    .paddr(m_apb_paddr), .pwdata(m_apb_pwdata),
    .prdata(m_apb_prdata), .pprot(m_apb_pprot), .pstrb(m_apb_pstrb),
    .req_valid(req_valid), .req_write(req_write),
    .rsp_valid(rsp_valid), .rsp_ready(rsp_ready),
    .rsp_error(rsp_error), .rsp_rdata(rsp_rdata),
    .awid_saved(u_axi4_lite_slave.awid_buf),
    .arid_saved(u_axi4_lite_slave.arid_buf)
);
`default_nettype wire
