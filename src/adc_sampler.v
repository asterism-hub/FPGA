`timescale 1ns / 1ps

module adc_sampler #(
    parameter integer DATA_WIDTH   = 8,
    parameter integer SAMPLE_COUNT = 1024
) (
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   enable,
    input  wire [DATA_WIDTH-1:0]  adc_data,
    input  wire                   sample_ready,
    output reg  [DATA_WIDTH-1:0]  sample_data,
    output reg                    sample_valid,
    output reg                    frame_start
);

    localparam integer COUNT_WIDTH = (SAMPLE_COUNT <= 1) ? 1 : $clog2(SAMPLE_COUNT);
    localparam [COUNT_WIDTH-1:0] SAMPLE_MAX = SAMPLE_COUNT - 1;

    reg  [COUNT_WIDTH-1:0] sample_count = {COUNT_WIDTH{1'b0}};
    wire                    frame_start_next = (sample_count == {COUNT_WIDTH{1'b0}});

    always @(posedge clk) begin
        if (rst || !enable) begin
            sample_count <= {COUNT_WIDTH{1'b0}};
        end else if (enable && sample_ready) begin
            if (sample_count == SAMPLE_MAX) begin
                sample_count <= {COUNT_WIDTH{1'b0}};
            end else begin
                sample_count <= sample_count + 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            sample_data  <= {DATA_WIDTH{1'b0}};
            sample_valid <= 1'b0;
            frame_start  <= 1'b0;
        end else begin
            if (enable && sample_ready) begin
                sample_data  <= adc_data;
                sample_valid <= 1'b1;
                frame_start  <= frame_start_next;
            end else if (!enable) begin
                sample_valid <= 1'b0;
                frame_start  <= 1'b0;
            end else begin
                sample_valid <= 1'b0;
                frame_start  <= 1'b0;
            end
        end
    end

endmodule
