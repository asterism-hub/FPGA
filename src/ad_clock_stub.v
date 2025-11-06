`timescale 1ns / 1ps

// 简化的 PLL 占位模块，用于仿真和综合占位。
// 实际工程请替换为厂商提供的 PLL/CLKGEN IP。
module ad_clock (
    input  wire clkin1,
    output wire pll_lock,
    output wire clkout0
);

    assign pll_lock = 1'b1;
    assign clkout0  = clkin1;

endmodule
