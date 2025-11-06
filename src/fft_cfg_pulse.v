`timescale 1ns / 1ps

module fft_cfg_pulse #(
    parameter integer ARM_CYCLES = 16
) (
    input  wire i_clk,
    input  wire i_rstn,
    output reg  o_cfg_valid,
    output wire o_cfg_data
);

    reg [$clog2(ARM_CYCLES+1)-1:0] arm_count;
    reg                            cfg_sent;

    assign o_cfg_data = 1'b1;

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            arm_count  <= {($clog2(ARM_CYCLES+1)){1'b0}};
            cfg_sent   <= 1'b0;
            o_cfg_valid <= 1'b0;
        end else begin
            if (!cfg_sent) begin
                if (arm_count == ARM_CYCLES) begin
                    o_cfg_valid <= 1'b1;
                    cfg_sent    <= 1'b1;
                end else begin
                    arm_count   <= arm_count + 1'b1;
                    o_cfg_valid <= 1'b0;
                end
            end else begin
                o_cfg_valid <= 1'b0;
            end
        end
    end

endmodule
