`timescale 1ns / 1ps

module hdmi_tx (
    input  wire       pix_clk,
    input  wire       de,
    input  wire       hsync,
    input  wire       vsync,
    input  wire [7:0] red,
    input  wire [7:0] green,
    input  wire [7:0] blue,
    output wire       tmds_clk_p,
    output wire       tmds_clk_n,
    output wire [2:0] tmds_d_p,
    output wire [2:0] tmds_d_n
);

    reg [2:0] data_shift;

    assign tmds_clk_p = pix_clk;
    assign tmds_clk_n = ~pix_clk;
    assign tmds_d_p   = data_shift;
    assign tmds_d_n   = ~data_shift;

    always @(posedge pix_clk) begin
        if (de) begin
            data_shift <= {blue[7], green[7], red[7]};
        end else begin
            data_shift <= {vsync, hsync, de};
        end
    end

endmodule
