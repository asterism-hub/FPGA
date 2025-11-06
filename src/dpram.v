`timescale 1ns / 1ps

module dpram #(
    parameter integer AW = 10,
    parameter integer DW = 16
) (
    input  wire             clka,
    input  wire [AW-1:0]    addra,
    input  wire [DW-1:0]    dina,
    input  wire             wea,
    input  wire             clkb,
    input  wire [AW-1:0]    addrb,
    output reg  [DW-1:0]    doutb
);

    localparam integer DEPTH = 1 << AW;

    reg [DW-1:0] mem [0:DEPTH-1];

    always @(posedge clka) begin
        if (wea) begin
            mem[addra] <= dina;
        end
    end

    always @(posedge clkb) begin
        doutb <= mem[addrb];
    end

endmodule
