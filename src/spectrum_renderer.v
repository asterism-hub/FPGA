`timescale 1ns / 1ps

module spectrum_renderer #(
    parameter integer NPOINT = 1024,
    parameter integer MAG_W  = 16
) (
    input  wire                   pix_clk,
    input  wire                   rstn,
    input  wire [11:0]            x,
    input  wire [11:0]            y,
    input  wire                   de,
    output reg  [$clog2(NPOINT/2)-1:0] ram_addr_b,
    input  wire [MAG_W-1:0]       ram_dout_b,
    output reg  [7:0]             r,
    output reg  [7:0]             g,
    output reg  [7:0]             b
);

    localparam integer BIN_COUNT  = NPOINT / 2;
    localparam integer H_ACTIVE   = 1280;
    localparam integer V_ACTIVE   = 720;
    localparam integer SCALE_BITS = (MAG_W > 10) ? (MAG_W - 10) : 0;

    reg [MAG_W-1:0] magnitude_sample;
    reg [MAG_W-1:0] magnitude_lat;

    wire [20:0] scaled_x = x * BIN_COUNT;
    wire [$clog2(BIN_COUNT)-1:0] bin_index = scaled_x / H_ACTIVE;

    wire [10:0] magnitude_scaled = (MAG_W > 10) ? (magnitude_lat >> SCALE_BITS) : (magnitude_lat << (10 - MAG_W));
    wire [11:0] bar_height = (magnitude_scaled >= V_ACTIVE) ? V_ACTIVE[11:0] : {1'b0, magnitude_scaled};
    wire [11:0] bar_base   = (V_ACTIVE > bar_height) ? (V_ACTIVE - bar_height) : 12'd0;

    reg [7:0] r_next;
    reg [7:0] g_next;
    reg [7:0] b_next;

    always @(posedge pix_clk or negedge rstn) begin
        if (!rstn) begin
            ram_addr_b        <= {($clog2(NPOINT/2)){1'b0}};
            magnitude_sample  <= {MAG_W{1'b0}};
            magnitude_lat     <= {MAG_W{1'b0}};
        end else begin
            ram_addr_b       <= bin_index;
            magnitude_sample <= ram_dout_b;
            magnitude_lat    <= magnitude_sample;
        end
    end

    always @(*) begin
        r_next = 8'h00;
        g_next = 8'h00;
        b_next = 8'h10;
        if (de) begin
            if (y >= bar_base) begin
                r_next = 8'h30;
                g_next = 8'hd0;
                b_next = 8'h30;
            end

            if ((y[4:0] == 5'd0) || (x[5:0] == 6'd0)) begin
                r_next = 8'h20;
                g_next = 8'h40;
                b_next = 8'h80;
            end
        end
    end

    always @(posedge pix_clk or negedge rstn) begin
        if (!rstn) begin
            r <= 8'd0;
            g <= 8'd0;
            b <= 8'd0;
        end else begin
            r <= r_next;
            g <= g_next;
            b <= b_next;
        end
    end

endmodule
