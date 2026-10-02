`timescale 1ns/1ps
`default_nettype none

// APB4 master backend, IHI0024C. Existing module and port names are kept.
// SETUP is exactly one cycle. ACCESS waits for PREADY without changing pins.
// Capture PRDATA/PSLVERR only at completion. Hold rsp_valid/data/error until
// rsp_ready acknowledges the response; do not overwrite an unaccepted one.
// This is an external APB bus master, not an APB register-bank slave.

module apb_master #(
    parameter integer addr_width = 32,
    parameter integer data_width = 32,
    parameter integer strb_width = 4
) (
    input  wire                  clk,
    input  wire                  rstn,
    input  wire                  req_valid,
    output wire                  req_ready,
    input  wire                  req_write,
    input  wire [addr_width-1:0]     req_addr,
    input  wire [data_width-1:0]     req_wdata,
    input  wire [strb_width-1:0]     req_strb,
    input  wire [2:0]                req_prot,
    output reg                   rsp_valid,
    input  wire                  rsp_ready,
    output reg  [data_width-1:0]     rsp_rdata,
    output reg                   rsp_error,

    output reg  [addr_width-1:0]     paddr,
    output reg  [2:0]                pprot,
    output wire                  psel,
    output wire                  penable,
    output reg                   pwrite,
    output reg  [data_width-1:0]     pwdata,
    output reg  [strb_width-1:0]     pstrb,
    input  wire [data_width-1:0]     prdata,
    input  wire                  pready,
    input  wire                  pslverr
);

    // synthesis translate_off
    initial begin
        if ((addr_width < 3) || (data_width != 32) || (strb_width != 4))
            $fatal(1, "apb_master: this bridge requires address >= 3, data=32, strb=4");
    end
    // synthesis translate_on

    localparam [1:0] APB_IDLE = 2'd0,
                     APB_SETUP = 2'd1,
                     APB_ACCESS = 2'd2,
                     APB_RESPONSE = 2'd3;
    reg [1:0] state;

    assign req_ready = rstn && (state == APB_IDLE);
    assign psel = rstn && ((state == APB_SETUP) || (state == APB_ACCESS));
    assign penable = rstn && (state == APB_ACCESS);

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= APB_IDLE;
            paddr <= {addr_width{1'b0}};
            pprot <= 3'b000;
            pwrite <= 1'b0;
            pwdata <= {data_width{1'b0}};
            pstrb <= {strb_width{1'b0}};
            rsp_valid <= 1'b0;
            rsp_rdata <= {data_width{1'b0}};
            rsp_error <= 1'b0;
        end else begin
            case (state)
                APB_IDLE: begin
                    if (req_valid && req_ready) begin
                        paddr <= req_addr;
                        pprot <= req_prot;
                        pwrite <= req_write;
                        pwdata <= req_write ? req_wdata : {data_width{1'b0}};
                        pstrb <= req_write ? req_strb : {strb_width{1'b0}};
                        state <= APB_SETUP;
                    end
                end
                APB_SETUP: state <= APB_ACCESS;
                APB_ACCESS: begin
                    if (pready) begin
                        rsp_rdata <= pwrite ? {data_width{1'b0}} : prdata;
                        rsp_error <= pslverr;
                        rsp_valid <= 1'b1;
                        state <= APB_RESPONSE;
                    end
                    // Otherwise stay in ACCESS and hold all request signals.
                end
                APB_RESPONSE: begin
                    if (rsp_valid && rsp_ready) begin
                        rsp_valid <= 1'b0;
                        state <= APB_IDLE;
                    end
                    // Hold response payload until the AXI frontend accepts it.
                end
                default: begin
                    state <= APB_IDLE;
                    rsp_valid <= 1'b0;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
