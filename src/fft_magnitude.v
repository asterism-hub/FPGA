`timescale 1ns / 1ps

module fft_magnitude #(
    parameter integer DATA_WIDTH = 16,
    parameter integer MAG_WIDTH  = 24
) (
    input  wire                   clk,
    input  wire                   rst,
    input  wire [DATA_WIDTH-1:0]  real_in,
    input  wire [DATA_WIDTH-1:0]  imag_in,
    input  wire                   valid_in,
    input  wire                   last_in,
    output reg  [MAG_WIDTH-1:0]   magnitude,
    output reg                    valid_out,
    output reg                    last_out
);

    localparam integer EXT_WIDTH   = DATA_WIDTH + 1;
    localparam integer SCALE_SHIFT = (MAG_WIDTH > EXT_WIDTH) ? (MAG_WIDTH - EXT_WIDTH) : 0;

    wire [EXT_WIDTH-1:0] abs_real_w;
    wire [EXT_WIDTH-1:0] abs_imag_w;
    wire [EXT_WIDTH-1:0] max_val_w;
    wire [EXT_WIDTH-1:0] min_val_w;
    wire [MAG_WIDTH-1:0] max_scaled_w;
    wire [MAG_WIDTH-1:0] min_scaled_w;
    wire [MAG_WIDTH-1:0] magnitude_w;

    function [EXT_WIDTH-1:0] abs_val;
        input [DATA_WIDTH-1:0] value;
        begin
            abs_val = value[DATA_WIDTH-1] ? ({1'b0, (~value + 1'b1)}) : {1'b0, value};
        end
    endfunction

    function [MAG_WIDTH-1:0] scale_value;
        input [EXT_WIDTH-1:0] value;
        begin
            if (MAG_WIDTH >= EXT_WIDTH) begin
                scale_value = value << SCALE_SHIFT;
            end else begin
                scale_value = value >> (EXT_WIDTH - MAG_WIDTH);
            end
        end
    endfunction

    assign abs_real_w = abs_val(real_in);
    assign abs_imag_w = abs_val(imag_in);

    assign max_val_w  = (abs_real_w >= abs_imag_w) ? abs_real_w : abs_imag_w;
    assign min_val_w  = (abs_real_w >= abs_imag_w) ? abs_imag_w : abs_real_w;

    assign max_scaled_w = scale_value(max_val_w);
    assign min_scaled_w = scale_value(min_val_w);

    assign magnitude_w = max_scaled_w + (min_scaled_w >> 1) + (min_scaled_w >> 2);

    always @(posedge clk) begin
        if (rst) begin
            magnitude <= {MAG_WIDTH{1'b0}};
            valid_out <= 1'b0;
            last_out  <= 1'b0;
        end else begin
            if (valid_in) begin
                magnitude <= magnitude_w;
                valid_out <= 1'b1;
                last_out  <= last_in;
            end else if (valid_out) begin
                valid_out <= 1'b0;
                last_out  <= 1'b0;
            end
        end
    end

endmodule
