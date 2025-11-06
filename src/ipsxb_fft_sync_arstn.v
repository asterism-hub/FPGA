`timescale 1ns / 1ps

module ipsxb_fft_sync_arstn (
    input  wire i_clk,
    input  wire i_arstn_presync,
    output wire o_arstn_synced
);

    reg [2:0] sync_reg;

    always @(posedge i_clk or negedge i_arstn_presync) begin
        if (!i_arstn_presync) begin
            sync_reg <= 3'b000;
        end else begin
            sync_reg <= {sync_reg[1:0], 1'b1};
        end
    end

    assign o_arstn_synced = sync_reg[2];

endmodule
