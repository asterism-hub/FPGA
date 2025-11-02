`timescale 1ns / 1ps

module adc_sampler #(
    parameter integer DATA_WIDTH = 12,
    parameter integer SCLK_DIV = 4,
    parameter integer SAMPLE_COUNT = 1024
) (
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   enable,
    // ADC serial interface
    output wire                   adc_sclk,
    output reg                    adc_cs_n,
    input  wire                   adc_dout,
    // Sample stream output
    output reg  [DATA_WIDTH-1:0]  sample_data,
    output reg                    sample_valid,
    input  wire                   sample_ready,
    output reg  [15:0]            sample_index,
    output reg                    frame_start
);

    localparam integer IDLE  = 0;
    localparam integer SHIFT = 1;
    localparam integer HOLD  = 2;

    reg [$clog2(SCLK_DIV)-1:0] clk_divider = 0;
    reg                        sclk_reg = 0;
    reg                        sclk_reg_d = 0;
    reg [DATA_WIDTH-1:0]       shift_reg = 0;
    reg [$clog2(DATA_WIDTH):0] bit_cnt = 0;
    reg [1:0]                  state = IDLE;

    assign adc_sclk = sclk_reg;

    wire sclk_toggle = (clk_divider == SCLK_DIV-1);
    wire sclk_rise;
    wire sclk_fall;

    assign sclk_rise = (sclk_reg_d == 1'b0) && (sclk_reg == 1'b1);
    assign sclk_fall = (sclk_reg_d == 1'b1) && (sclk_reg == 1'b0);

    always @(posedge clk) begin
        if (rst) begin
            clk_divider <= 0;
            sclk_reg    <= 0;
        end else if (enable) begin
            if (sclk_toggle) begin
                clk_divider <= 0;
                sclk_reg    <= ~sclk_reg;
            end else begin
                clk_divider <= clk_divider + 1'b1;
            end
        end else begin
            clk_divider <= 0;
            sclk_reg    <= 0;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            sclk_reg_d <= 0;
        end else begin
            sclk_reg_d <= sclk_reg;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            adc_cs_n     <= 1'b1;
            sample_valid <= 1'b0;
            bit_cnt      <= 0;
            shift_reg    <= {DATA_WIDTH{1'b0}};
            state        <= IDLE;
            sample_index <= 0;
            frame_start  <= 1'b0;
        end else begin
            sample_valid <= 1'b0;
            frame_start  <= 1'b0;

            case (state)
                IDLE: begin
                    if (enable && sample_ready) begin
                        adc_cs_n <= 1'b0;
                        bit_cnt  <= DATA_WIDTH;
                        state    <= SHIFT;
                        if (sample_index == 0) begin
                            frame_start <= 1'b1;
                        end
                    end
                end
                SHIFT: begin
                    if (sclk_rise) begin
                        shift_reg <= {shift_reg[DATA_WIDTH-2:0], adc_dout};
                        if (bit_cnt == 1) begin
                            state <= HOLD;
                        end
                        bit_cnt <= bit_cnt - 1'b1;
                    end
                end
                HOLD: begin
                    adc_cs_n     <= 1'b1;
                    sample_data  <= shift_reg;
                    sample_valid <= 1'b1;
                    state        <= enable ? IDLE : HOLD;

                    if (sample_index == SAMPLE_COUNT-1) begin
                        sample_index <= 0;
                    end else begin
                        sample_index <= sample_index + 1'b1;
                    end
                end
                default: state <= IDLE;
            endcase

            if (!enable) begin
                adc_cs_n     <= 1'b1;
                state        <= IDLE;
                bit_cnt      <= 0;
            end
        end
    end

endmodule
