`timescale 1ns / 1ps

module adc_to_fft_axis #(
    parameter integer NPOINT    = 1024,
    parameter integer DIN_W     = 16,
    parameter integer USE_ASYNC = 1
) (
    input  wire                 adc_clk,
    input  wire                 adc_rstn,
    input  wire [7:0]           adc_data,
    input  wire                 sys_clk,
    input  wire                 sys_rstn,
    output wire                 s_tvalid,
    input  wire                 s_tready,
    output wire                 s_tlast,
    output wire [2*DIN_W-1:0]   s_tdata
);

    localparam integer FIFO_DEPTH = NPOINT;
    localparam integer INDEX_W    = (NPOINT > 1) ? $clog2(NPOINT) : 1;

    wire [DIN_W-1:0] adc_ext = {{(DIN_W-8){adc_data[7]}}, adc_data};

    wire fifo_rd_valid;
    wire fifo_rd_ready;
    wire [DIN_W-1:0] fifo_rd_data;

    generate
        if (USE_ASYNC) begin : g_async_fifo
            axis_async_fifo #(
                .WIDTH(DIN_W),
                .DEPTH(FIFO_DEPTH)
            ) u_async_fifo (
                .wr_clk (adc_clk),
                .wr_rstn(adc_rstn),
                .wr_valid(1'b1),
                .wr_ready(),
                .wr_data (adc_ext),
                .rd_clk (sys_clk),
                .rd_rstn(sys_rstn),
                .rd_valid(fifo_rd_valid),
                .rd_ready(fifo_rd_ready),
                .rd_data (fifo_rd_data)
            );
        end else begin : g_sync_fifo
            reg [DIN_W-1:0] sample_reg;
            reg             sample_valid;

            assign fifo_rd_data  = sample_reg;
            assign fifo_rd_valid = sample_valid;

            always @(posedge sys_clk or negedge sys_rstn) begin
                if (!sys_rstn) begin
                    sample_reg   <= {DIN_W{1'b0}};
                    sample_valid <= 1'b0;
                end else begin
                    if (fifo_rd_ready) begin
                        sample_reg   <= adc_ext;
                        sample_valid <= 1'b1;
                    end else if (!sample_valid) begin
                        sample_reg   <= adc_ext;
                        sample_valid <= 1'b1;
                    end
                end
            end
        end
    endgenerate

    reg [DIN_W-1:0] sample_hold;
    reg             valid_r;
    reg             last_r;
    reg [INDEX_W-1:0] sample_index;

    assign s_tvalid = valid_r;
    assign s_tlast  = last_r;
    assign s_tdata  = {{DIN_W{1'b0}}, sample_hold};

    assign fifo_rd_ready = (!valid_r || (valid_r && s_tready)) && fifo_rd_valid;

    always @(posedge sys_clk or negedge sys_rstn) begin
        if (!sys_rstn) begin
            sample_hold  <= {DIN_W{1'b0}};
            valid_r      <= 1'b0;
            last_r       <= 1'b0;
            sample_index <= {INDEX_W{1'b0}};
        end else begin
            if (!valid_r || (valid_r && s_tready)) begin
                if (fifo_rd_valid) begin
                    sample_hold <= fifo_rd_data;
                    valid_r     <= 1'b1;
                    last_r      <= (sample_index == NPOINT-1);
                    if (sample_index == NPOINT-1) begin
                        sample_index <= {INDEX_W{1'b0}};
                    end else begin
                        sample_index <= sample_index + 1'b1;
                    end
                end else begin
                    valid_r <= 1'b0;
                    last_r  <= 1'b0;
                end
            end else begin
                // Hold value until downstream ready
                valid_r <= valid_r;
                last_r  <= last_r;
            end
        end
    end

endmodule

// -----------------------------------------------------------------------------
// Dual clock AXI-Stream style FIFO used for CDC between adc_clk and sys_clk
// -----------------------------------------------------------------------------
module axis_async_fifo #(
    parameter integer WIDTH = 16,
    parameter integer DEPTH = 1024
) (
    input  wire               wr_clk,
    input  wire               wr_rstn,
    input  wire               wr_valid,
    output wire               wr_ready,
    input  wire [WIDTH-1:0]   wr_data,
    input  wire               rd_clk,
    input  wire               rd_rstn,
    output reg                rd_valid,
    input  wire               rd_ready,
    output reg  [WIDTH-1:0]   rd_data
);

    localparam integer ADDR_WIDTH = (DEPTH > 1) ? $clog2(DEPTH) : 1;
    localparam integer PTR_WIDTH  = ADDR_WIDTH + 1;
    localparam integer FIFO_SIZE  = 1 << ADDR_WIDTH;

    reg [WIDTH-1:0] mem [0:FIFO_SIZE-1];

    reg [PTR_WIDTH-1:0] wr_ptr_bin;
    reg [PTR_WIDTH-1:0] wr_ptr_gray;
    reg [PTR_WIDTH-1:0] rd_ptr_bin;
    reg [PTR_WIDTH-1:0] rd_ptr_gray;

    reg [PTR_WIDTH-1:0] rd_ptr_gray_sync1;
    reg [PTR_WIDTH-1:0] rd_ptr_gray_sync2;
    reg [PTR_WIDTH-1:0] wr_ptr_gray_sync1;
    reg [PTR_WIDTH-1:0] wr_ptr_gray_sync2;

    function [PTR_WIDTH-1:0] bin2gray;
        input [PTR_WIDTH-1:0] bin;
        begin
            bin2gray = (bin >> 1) ^ bin;
        end
    endfunction

    wire [PTR_WIDTH-1:0] wr_ptr_bin_next  = wr_ptr_bin + (wr_valid && wr_ready);
    wire [PTR_WIDTH-1:0] wr_ptr_gray_next = bin2gray(wr_ptr_bin_next);
    wire [PTR_WIDTH-1:0] rd_ptr_bin_next  = rd_ptr_bin + ((rd_valid && rd_ready) ? 1'b1 : 1'b0);
    wire [PTR_WIDTH-1:0] rd_ptr_gray_next = bin2gray(rd_ptr_bin_next);

    wire [PTR_WIDTH-1:0] rd_ptr_gray_sync = rd_ptr_gray_sync2;
    wire [PTR_WIDTH-1:0] wr_ptr_gray_sync = wr_ptr_gray_sync2;

    wire [PTR_WIDTH-1:0] rd_gray_inverted;
    wire full;
    wire empty;

    generate
        if (PTR_WIDTH > 2) begin : g_full_detect
            assign rd_gray_inverted = {~rd_ptr_gray_sync[PTR_WIDTH-1:PTR_WIDTH-2], rd_ptr_gray_sync[PTR_WIDTH-3:0]};
        end else begin : g_full_detect_small
            assign rd_gray_inverted = {~rd_ptr_gray_sync[1], rd_ptr_gray_sync[0]};
        end
    endgenerate

    assign full  = (wr_ptr_gray_next == rd_gray_inverted);
    assign empty = (rd_ptr_gray == wr_ptr_gray_sync);
    assign wr_ready = ~full;

    always @(posedge wr_clk or negedge wr_rstn) begin
        if (!wr_rstn) begin
            wr_ptr_bin        <= {PTR_WIDTH{1'b0}};
            wr_ptr_gray       <= {PTR_WIDTH{1'b0}};
            rd_ptr_gray_sync1 <= {PTR_WIDTH{1'b0}};
            rd_ptr_gray_sync2 <= {PTR_WIDTH{1'b0}};
        end else begin
            rd_ptr_gray_sync1 <= rd_ptr_gray;
            rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;

            if (wr_valid && wr_ready) begin
                mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= wr_data;
                wr_ptr_bin  <= wr_ptr_bin_next;
                wr_ptr_gray <= wr_ptr_gray_next;
            end
        end
    end

    always @(posedge rd_clk or negedge rd_rstn) begin
        if (!rd_rstn) begin
            rd_ptr_bin        <= {PTR_WIDTH{1'b0}};
            rd_ptr_gray       <= {PTR_WIDTH{1'b0}};
            wr_ptr_gray_sync1 <= {PTR_WIDTH{1'b0}};
            wr_ptr_gray_sync2 <= {PTR_WIDTH{1'b0}};
            rd_valid          <= 1'b0;
            rd_data           <= {WIDTH{1'b0}};
        end else begin
            wr_ptr_gray_sync1 <= wr_ptr_gray;
            wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;

            if (rd_valid && rd_ready) begin
                rd_ptr_bin  <= rd_ptr_bin_next;
                rd_ptr_gray <= rd_ptr_gray_next;
                rd_valid    <= 1'b0;
            end

            if (!empty) begin
                if (!rd_valid || (rd_valid && rd_ready)) begin
                    rd_data  <= mem[rd_ptr_bin[ADDR_WIDTH-1:0]];
                    rd_valid <= 1'b1;
                end
            end else if (rd_valid && rd_ready) begin
                rd_valid <= 1'b0;
            end
        end
    end

endmodule
