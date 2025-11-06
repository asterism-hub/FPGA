`timescale 1ns / 1ps

module fft_mag_store #(
    parameter integer NPOINT = 1024,
    parameter integer DOUT_W = 16,
    parameter integer MAG_W  = 16
) (
    input  wire                     sys_clk,
    input  wire                     sys_rstn,
    input  wire                     m_tvalid,
    input  wire                     m_tlast,
    input  wire signed [DOUT_W-1:0] m_tdata_re,
    input  wire signed [DOUT_W-1:0] m_tdata_im,
    output reg  [$clog2(NPOINT/2)-1:0] ram_addr_a,
    output reg  [MAG_W-1:0]            ram_din_a,
    output reg                        ram_we_a
);

    localparam integer HALF_POINTS = NPOINT / 2;
    localparam integer ADDR_WIDTH  = (HALF_POINTS > 1) ? $clog2(HALF_POINTS) : 1;

    wire [MAG_W-1:0] magnitude_value;
    wire             magnitude_valid;
    wire             magnitude_last;

    fft_magnitude #(
        .DATA_WIDTH(DOUT_W),
        .MAG_WIDTH (MAG_W)
    ) u_fft_mag (
        .clk      (sys_clk),
        .rst      (~sys_rstn),
        .real_in  (m_tdata_re),
        .imag_in  (m_tdata_im),
        .valid_in (m_tvalid),
        .last_in  (m_tlast),
        .magnitude(magnitude_value),
        .valid_out(magnitude_valid),
        .last_out (magnitude_last)
    );

    reg [ADDR_WIDTH-1:0] write_addr;

    always @(posedge sys_clk or negedge sys_rstn) begin
        if (!sys_rstn) begin
            ram_we_a    <= 1'b0;
            write_addr  <= {ADDR_WIDTH{1'b0}};
            ram_addr_a  <= {ADDR_WIDTH{1'b0}};
            ram_din_a   <= {MAG_W{1'b0}};
        end else begin
            ram_we_a <= 1'b0;
            if (magnitude_valid) begin
                ram_we_a   <= 1'b1;
                ram_addr_a <= write_addr;
                ram_din_a  <= magnitude_value;
                if (write_addr == (HALF_POINTS-1)) begin
                    write_addr <= {ADDR_WIDTH{1'b0}};
                end else begin
                    write_addr <= write_addr + 1'b1;
                end
            end
        end
    end

endmodule
