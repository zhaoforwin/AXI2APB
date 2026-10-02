`timescale 1ns/1ps
`default_nettype none

// AXI5-Lite slave frontend. The legacy module/port/parameter names are kept
// to match the user's axilite2apb top. ID and SIZE ports are additions.
// 32-bit data, one pending write and one pending read, in-order responses.
// AW/W are independent. Every accepted request retains its ID until response.
// The internal req/rsp interfaces both use VALID/READY handshakes.
// Read data contains the full 32-bit word, permitted by IHI0022G C2.6.

module axi4_lite_slave #(
    parameter integer addr_width = 32,
    parameter integer data_width = 32,
    parameter integer strb_width = 4,
    parameter integer id_width = 4
) (
    input  wire                  aclk,
    input  wire                  aresetn,
    input  wire [addr_width-1:0]     awaddr,
    input  wire [id_width-1:0]       awid,
    input  wire [2:0]                awsize,
    input  wire [2:0]                awprot,
    input  wire                  awvalid,
    output wire                  awready,
    input  wire [data_width-1:0]     wdata,
    input  wire [strb_width-1:0]     wstrb,
    input  wire                  wvalid,
    output wire                  wready,
    output reg  [1:0]                bresp,
    output reg  [id_width-1:0]       bid,
    output reg                   bvalid,
    input  wire                  bready,
    input  wire [addr_width-1:0]     araddr,
    input  wire [id_width-1:0]       arid,
    input  wire [2:0]                arsize,
    input  wire [2:0]                arprot,
    input  wire                  arvalid,
    output wire                  arready,
    output reg  [data_width-1:0]     rdata,
    output reg  [1:0]                rresp,
    output reg  [id_width-1:0]       rid,
    output reg                   rvalid,
    input  wire                  rready,

    output wire                  req_valid,
    input  wire                  req_ready,
    output reg                   req_write,
    output reg  [addr_width-1:0]     req_addr,
    output reg  [data_width-1:0]     req_wdata,
    output reg  [strb_width-1:0]     req_strb,
    output reg  [2:0]                req_prot,
    input  wire                  rsp_valid,
    output wire                  rsp_ready,
    input  wire [data_width-1:0]     rsp_rdata,
    input  wire                  rsp_error
);

    // synthesis translate_off
    initial begin
        if ((addr_width < 3) || (data_width != 32) || (strb_width != 4) || (id_width < 1))
            $fatal(1, "axi4_lite_slave: this bridge requires address >= 3, data=32, strb=4, id>=1");
    end
    // synthesis translate_on

    localparam [1:0] FRONT_IDLE = 2'd0,
                     FRONT_ISSUE = 2'd1,
                     FRONT_WAIT = 2'd2;
    reg [1:0] state;

    reg aw_full, w_full, ar_full;
    reg [addr_width-1:0] awaddr_buf, araddr_buf;
    reg [2:0] awprot_buf, arprot_buf;
    reg [id_width-1:0] awid_buf, arid_buf;
    reg [2:0] awsize_buf, arsize_buf;
    reg [data_width-1:0] wdata_buf;
    reg [strb_width-1:0] wstrb_buf;
    reg prefer_read;

    wire write_pending = aw_full && w_full && !bvalid;
    wire read_pending = ar_full && !rvalid;
    wire select_write = write_pending && (!read_pending || !prefer_read);

    wire [addr_width-1:0] selected_addr = select_write ? awaddr_buf : araddr_buf;

    // Only the security attribute AxPROT[1] has AXI5-Lite meaning.
    // All three bits are preserved for the existing APB protection interface.
    // Drive unused AxPROT[2] and AxPROT[0] to zero in an AXI5-Lite system.
    assign awready = aresetn && !aw_full;
    assign wready = aresetn && !w_full;
    assign arready = aresetn && !ar_full;
    assign req_valid = aresetn && (state == FRONT_ISSUE);
    assign rsp_ready = aresetn && (state == FRONT_WAIT);

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state <= FRONT_IDLE;
            aw_full <= 1'b0;
            w_full <= 1'b0;
            ar_full <= 1'b0;
            awaddr_buf <= {addr_width{1'b0}};
            araddr_buf <= {addr_width{1'b0}};
            awprot_buf <= 3'b000;
            arprot_buf <= 3'b000;
            awid_buf <= {id_width{1'b0}};
            arid_buf <= {id_width{1'b0}};
            awsize_buf <= 3'b010;
            arsize_buf <= 3'b010;
            wdata_buf <= {data_width{1'b0}};
            wstrb_buf <= {strb_width{1'b0}};
            prefer_read <= 1'b0;
            bvalid <= 1'b0;
            bresp <= 2'b00;
            bid <= {id_width{1'b0}};
            rvalid <= 1'b0;
            rresp <= 2'b00;
            rid <= {id_width{1'b0}};
            rdata <= {data_width{1'b0}};
            req_write <= 1'b0;
            req_addr <= {addr_width{1'b0}};
            req_wdata <= {data_width{1'b0}};
            req_strb <= {strb_width{1'b0}};
            req_prot <= 3'b000;
        end else begin
            if (awvalid && awready) begin
                aw_full <= 1'b1;
                awaddr_buf <= awaddr;
                awprot_buf <= awprot;
                awid_buf <= awid;
                awsize_buf <= awsize;
            end
            if (wvalid && wready) begin
                w_full <= 1'b1;
                wdata_buf <= wdata;
                wstrb_buf <= wstrb;
            end
            if (arvalid && arready) begin
                ar_full <= 1'b1;
                araddr_buf <= araddr;
                arprot_buf <= arprot;
                arid_buf <= arid;
                arsize_buf <= arsize;
            end

            // Keep VALID and response payload stable under backpressure.
            if (bvalid && bready) begin
                bvalid <= 1'b0;
                aw_full <= 1'b0;
                w_full <= 1'b0;
            end
            if (rvalid && rready) begin
                rvalid <= 1'b0;
                ar_full <= 1'b0;
            end

            case (state)
                FRONT_IDLE: begin
                    if (write_pending || read_pending) begin
                        // A 32-bit AXI5-Lite bus accepts 1/2/4-byte transfers.
                        // Oversized requests are rejected locally, without APB.
                        if (select_write && (awsize_buf > 3'b010)) begin
                            bvalid <= 1'b1;
                            bresp <= 2'b10;
                            bid <= awid_buf;
                            prefer_read <= 1'b1;
                        end else if (!select_write && (arsize_buf > 3'b010)) begin
                            rvalid <= 1'b1;
                            rresp <= 2'b10;
                            rdata <= {data_width{1'b0}};
                            rid <= arid_buf;
                            prefer_read <= 1'b0;
                        end else begin
                            req_write <= select_write;
                            // APB reads the containing 32-bit register. For
                            // narrow writes, WSTRB selects its valid byte lanes.
                            req_addr <= {selected_addr[addr_width-1:2], 2'b00};
                            req_prot <= select_write ? awprot_buf : arprot_buf;
                            req_wdata <= select_write ? wdata_buf : {data_width{1'b0}};
                            req_strb <= select_write ? wstrb_buf : {strb_width{1'b0}};
                            state <= FRONT_ISSUE;
                        end
                    end
                end
                FRONT_ISSUE: begin
                    if (req_ready) begin
                        // Alternate priority when both directions are pending.
                        prefer_read <= req_write;
                        state <= FRONT_WAIT;
                    end
                end
                FRONT_WAIT: begin
                    if (rsp_valid && rsp_ready) begin
                        if (req_write) begin
                            bresp <= rsp_error ? 2'b10 : 2'b00;
                            bid <= awid_buf;
                            bvalid <= 1'b1;
                        end else begin
                            rdata <= rsp_rdata;
                            rresp <= rsp_error ? 2'b10 : 2'b00;
                            rid <= arid_buf;
                            rvalid <= 1'b1;
                        end
                        state <= FRONT_IDLE;
                    end
                end
                default: state <= FRONT_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
