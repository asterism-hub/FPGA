`timescale 1ns / 1ps

module vt_720p (
    input  wire        pix_clk,
    input  wire        rstn,
    output reg  [11:0] x,
    output reg  [11:0] y,
    output reg         de,
    output reg         hsync,
    output reg         vsync
);

    localparam integer H_ACTIVE = 1280;
    localparam integer H_FRONT  = 110;
    localparam integer H_SYNC   = 40;
    localparam integer H_BACK   = 220;
    localparam integer H_TOTAL  = H_ACTIVE + H_FRONT + H_SYNC + H_BACK;

    localparam integer V_ACTIVE = 720;
    localparam integer V_FRONT  = 5;
    localparam integer V_SYNC   = 5;
    localparam integer V_BACK   = 20;
    localparam integer V_TOTAL  = V_ACTIVE + V_FRONT + V_SYNC + V_BACK;

    reg [11:0] h_count;
    reg [11:0] v_count;

    always @(posedge pix_clk or negedge rstn) begin
        if (!rstn) begin
            h_count <= 12'd0;
            v_count <= 12'd0;
        end else begin
            if (h_count == H_TOTAL - 1) begin
                h_count <= 12'd0;
                if (v_count == V_TOTAL - 1) begin
                    v_count <= 12'd0;
                end else begin
                    v_count <= v_count + 12'd1;
                end
            end else begin
                h_count <= h_count + 12'd1;
            end
        end
    end

    always @(posedge pix_clk or negedge rstn) begin
        if (!rstn) begin
            x     <= 12'd0;
            y     <= 12'd0;
            de    <= 1'b0;
            hsync <= 1'b1;
            vsync <= 1'b1;
        end else begin
            de <= (h_count < H_ACTIVE) && (v_count < V_ACTIVE);
            if (h_count < H_ACTIVE) begin
                x <= h_count;
            end else begin
                x <= 12'd0;
            end

            if (v_count < V_ACTIVE) begin
                y <= v_count;
            end else begin
                y <= 12'd0;
            end

            hsync <= ~((h_count >= (H_ACTIVE + H_FRONT)) && (h_count < (H_ACTIVE + H_FRONT + H_SYNC)));
            vsync <= ~((v_count >= (V_ACTIVE + V_FRONT)) && (v_count < (V_ACTIVE + V_FRONT + V_SYNC)));
        end
    end

endmodule
