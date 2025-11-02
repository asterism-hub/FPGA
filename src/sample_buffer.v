`timescale 1ns / 1ps

module sample_buffer #(
    parameter integer DATA_WIDTH   = 12,
    parameter integer SAMPLE_COUNT = 1024
) (
    input  wire                   clk,
    input  wire                   rst,
    input  wire [DATA_WIDTH-1:0]  sample_in,
    input  wire                   sample_valid,
    output wire                   sample_ready,
    output reg                    frame_available,
    input  wire                   start_fft,
    output reg  [DATA_WIDTH-1:0]  fft_sample,
    output reg                    fft_valid,
    input  wire                   fft_ready,
    output reg                    fft_last
);

    localparam integer ADDR_WIDTH = $clog2(SAMPLE_COUNT);

    reg [DATA_WIDTH-1:0] ping_buffer [0:SAMPLE_COUNT-1];
    reg [DATA_WIDTH-1:0] pong_buffer [0:SAMPLE_COUNT-1];

    reg                  write_bank = 0;
    reg [ADDR_WIDTH:0]   write_ptr = 0;
    reg                  buffer_full = 0;

    reg                  read_bank = 0;
    reg [ADDR_WIDTH:0]   read_ptr = 0;
    reg                  reading = 0;

    assign sample_ready = 1'b1;

    integer i;

    always @(posedge clk) begin
        if (rst) begin
            write_ptr       <= 0;
            write_bank      <= 0;
            frame_available <= 1'b0;
            buffer_full     <= 1'b0;
        end else begin
            if (sample_valid) begin
                if (write_bank == 1'b0) begin
                    ping_buffer[write_ptr] <= sample_in;
                end else begin
                    pong_buffer[write_ptr] <= sample_in;
                end

                if (write_ptr == SAMPLE_COUNT-1) begin
                    write_ptr       <= 0;
                    frame_available <= 1'b1;
                    buffer_full     <= 1'b1;
                    write_bank      <= ~write_bank;
                end else begin
                    write_ptr <= write_ptr + 1'b1;
                end
            end

            if (frame_available && start_fft && !reading) begin
                read_bank       <= ~write_bank;
                reading         <= 1'b1;
                frame_available <= 1'b0;
                read_ptr        <= 0;
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            fft_valid <= 1'b0;
            fft_last  <= 1'b0;
            read_ptr  <= 0;
            reading   <= 1'b0;
        end else begin
            if (reading) begin
                if (!fft_valid || (fft_valid && fft_ready)) begin
                    if (read_bank == 1'b0) begin
                        fft_sample <= ping_buffer[read_ptr];
                    end else begin
                        fft_sample <= pong_buffer[read_ptr];
                    end

                    fft_valid <= 1'b1;
                    fft_last  <= (read_ptr == SAMPLE_COUNT-1);

                    if (fft_ready || !fft_valid) begin
                        if (read_ptr == SAMPLE_COUNT-1) begin
                            read_ptr <= 0;
                            reading  <= 1'b0;
                        end else begin
                            read_ptr <= read_ptr + 1'b1;
                        end
                    end
                end
            end else if (fft_valid && fft_ready) begin
                fft_valid <= 1'b0;
                fft_last  <= 1'b0;
            end
        end
    end

endmodule
