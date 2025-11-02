`timescale 1ns / 1ps

module signal_metrics #(
    parameter integer DATA_WIDTH    = 12,
    parameter integer SAMPLE_COUNT  = 1024,
    parameter integer SAMPLE_RATE   = 500000,
    parameter integer FFT_POINTS    = 1024,
    parameter integer MAG_WIDTH     = 24
) (
    input  wire                          clk,
    input  wire                          rst,
    input  wire [DATA_WIDTH-1:0]         sample_data,
    input  wire                          sample_valid,
    input  wire                          frame_start,
    input  wire [MAG_WIDTH-1:0]          magnitude_in,
    input  wire                          magnitude_valid,
    input  wire                          magnitude_last,
    input  wire [$clog2(FFT_POINTS)-1:0] magnitude_index,
    output reg  [DATA_WIDTH+3:0]         amplitude,
    output reg  [31:0]                   frequency_hz,
    output reg  [15:0]                   duty_cycle_permille,
    output reg  [15:0]                   thd_tenths_percent
);

    localparam integer FFT_HALF      = FFT_POINTS / 2;
    localparam integer INDEX_WIDTH   = $clog2(FFT_HALF);
    localparam integer THD_WIDTH     = 2 * MAG_WIDTH + 4;

    reg signed [DATA_WIDTH:0] sample_signed;
    reg signed [DATA_WIDTH:0] min_sample;
    reg signed [DATA_WIDTH:0] max_sample;
    reg [31:0]                high_count;
    reg [31:0]                sample_count;
    reg                       prev_sign;
    reg [15:0]                zero_crossings;
    reg                       frame_active;

    wire frame_done = sample_valid && (sample_count == SAMPLE_COUNT-1);

    always @(posedge clk) begin
        if (rst) begin
            min_sample      <= {DATA_WIDTH+1{1'b0}};
            max_sample      <= {DATA_WIDTH+1{1'b0}};
            high_count      <= 32'd0;
            sample_count    <= 32'd0;
            zero_crossings  <= 16'd0;
            prev_sign       <= 1'b0;
            frame_active    <= 1'b0;
            amplitude       <= {(DATA_WIDTH+4){1'b0}};
            frequency_hz    <= 32'd0;
            duty_cycle_permille <= 16'd0;
        end else begin
            if (frame_start) begin
                sample_signed <= {sample_data[DATA_WIDTH-1], sample_data};
                min_sample    <= {sample_data[DATA_WIDTH-1], sample_data};
                max_sample    <= {sample_data[DATA_WIDTH-1], sample_data};
                high_count    <= {31'd0, (sample_data[DATA_WIDTH-1] == 1'b0)};
                sample_count  <= 32'd0;
                zero_crossings<= 16'd0;
                prev_sign     <= sample_data[DATA_WIDTH-1];
                frame_active  <= 1'b1;
            end else if (sample_valid && frame_active) begin
                sample_signed <= {sample_data[DATA_WIDTH-1], sample_data};

                if ({sample_data[DATA_WIDTH-1], sample_data} < min_sample) begin
                    min_sample <= {sample_data[DATA_WIDTH-1], sample_data};
                end
                if ({sample_data[DATA_WIDTH-1], sample_data} > max_sample) begin
                    max_sample <= {sample_data[DATA_WIDTH-1], sample_data};
                end

                if (sample_data[DATA_WIDTH-1] == 1'b0) begin
                    high_count <= high_count + 1'b1;
                end

                if (prev_sign && (sample_data[DATA_WIDTH-1] == 1'b0)) begin
                    zero_crossings <= zero_crossings + 1'b1;
                end
                prev_sign    <= sample_data[DATA_WIDTH-1];

                if (sample_count < SAMPLE_COUNT-1) begin
                    sample_count <= sample_count + 1'b1;
                end

                if (frame_done) begin
                    frame_active <= 1'b0;

                    amplitude <= (max_sample - min_sample) >>> 1;

                    if (zero_crossings != 0) begin
                        frequency_hz <= (zero_crossings * SAMPLE_RATE) / SAMPLE_COUNT;
                    end else begin
                        frequency_hz <= 32'd0;
                    end

                    duty_cycle_permille <= (high_count * 1000) / SAMPLE_COUNT;
                end
            end
        end
    end

    // FFT magnitude buffering for THD calculations
    reg [MAG_WIDTH-1:0] mag_buffer [0:FFT_HALF-1];
    reg                 fft_frame_ready;
    reg [INDEX_WIDTH-1:0] read_index;
    reg [MAG_WIDTH-1:0]   fundamental_mag;
    reg [INDEX_WIDTH-1:0] fundamental_bin;
    reg [THD_WIDTH-1:0]   harmonic_sum;
    reg [THD_WIDTH-1:0]   fundamental_sq;
    reg [2:0]             harmonic_idx;
    reg [1:0]             thd_state;

    localparam integer THD_IDLE      = 0;
    localparam integer THD_FIND_FUND = 1;
    localparam integer THD_ACCUM     = 2;
    localparam integer THD_DONE      = 3;

    integer i;

    always @(posedge clk) begin
        if (rst) begin
            fft_frame_ready <= 1'b0;
            read_index      <= {INDEX_WIDTH{1'b0}};
            fundamental_mag <= {MAG_WIDTH{1'b0}};
            fundamental_bin <= {INDEX_WIDTH{1'b0}};
            harmonic_sum    <= {THD_WIDTH{1'b0}};
            fundamental_sq  <= {THD_WIDTH{1'b0}};
            harmonic_idx    <= 3'd2;
            thd_state       <= THD_IDLE;
            thd_tenths_percent <= 16'd0;
        end else begin
            if (magnitude_valid && (magnitude_index < FFT_HALF)) begin
                mag_buffer[magnitude_index[INDEX_WIDTH-1:0]] <= magnitude_in;
            end

            if (magnitude_valid && magnitude_last) begin
                fft_frame_ready <= 1'b1;
                thd_state       <= THD_FIND_FUND;
                read_index      <= {{(INDEX_WIDTH-1){1'b0}}, 1'b1};
                fundamental_mag <= {MAG_WIDTH{1'b0}};
                fundamental_bin <= {INDEX_WIDTH{1'b0}};
                harmonic_sum    <= {THD_WIDTH{1'b0}};
                fundamental_sq  <= {THD_WIDTH{1'b0}};
                harmonic_idx    <= 3'd2;
            end

            case (thd_state)
                THD_FIND_FUND: begin
                    if (read_index < FFT_HALF) begin
                        if (mag_buffer[read_index] > fundamental_mag) begin
                            fundamental_mag <= mag_buffer[read_index];
                            fundamental_bin <= read_index;
                        end
                        read_index <= read_index + 1'b1;
                    end else begin
                        fundamental_sq <= fundamental_mag * fundamental_mag;
                        harmonic_idx   <= 3'd2;
                        thd_state      <= THD_ACCUM;
                    end
                end
                THD_ACCUM: begin
                    if ((fundamental_bin != 0) && (harmonic_idx <= 3'd5)) begin
                        if (fundamental_bin * harmonic_idx < FFT_HALF) begin
                            harmonic_sum <= harmonic_sum +
                                mag_buffer[fundamental_bin * harmonic_idx] *
                                mag_buffer[fundamental_bin * harmonic_idx];
                        end
                        harmonic_idx <= harmonic_idx + 1'b1;
                    end else begin
                        thd_state <= THD_DONE;
                    end
                end
                THD_DONE: begin
                    if (fundamental_sq != 0) begin
                        thd_tenths_percent <= (harmonic_sum * 1000) / fundamental_sq;
                    end else begin
                        thd_tenths_percent <= 16'd0;
                    end
                    thd_state       <= THD_IDLE;
                    fft_frame_ready <= 1'b0;
                end
                default: begin
                    // Idle
                end
            endcase
        end
    end

endmodule
