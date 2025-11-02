`timescale 1ns / 1ps

module spectrum_analyzer_top #(
    parameter integer ADC_WIDTH      = 12,
    parameter integer FFT_POINTS     = 1024,
    parameter integer FFT_IP_WIDTH   = 16,
    parameter integer MAG_WIDTH      = 24,
    parameter integer SAMPLE_RATE    = 500000,
    parameter integer H_RES          = 640,
    parameter integer V_RES          = 480
) (
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   enable,
    // ADC interface
    output wire                   adc_sclk,
    output wire                   adc_cs_n,
    input  wire                   adc_dout,
    // Video pixel interface
    input  wire [11:0]            pixel_x,
    input  wire [11:0]            pixel_y,
    input  wire                   pixel_valid,
    output wire [15:0]            pixel_rgb,
    output wire                   pixel_ready
);

    localparam integer SAMPLE_COUNT = FFT_POINTS;
    localparam integer INDEX_WIDTH  = $clog2(FFT_POINTS);

    wire [ADC_WIDTH-1:0]          sample_data;
    wire                          sample_valid;
    wire                          frame_start;
    wire [15:0]                   sample_index;
    wire                          sample_ready;

    adc_sampler #(
        .DATA_WIDTH(ADC_WIDTH),
        .SCLK_DIV(4),
        .SAMPLE_COUNT(SAMPLE_COUNT)
    )
    u_adc_sampler (
        .clk(clk),
        .rst(rst),
        .enable(enable),
        .adc_sclk(adc_sclk),
        .adc_cs_n(adc_cs_n),
        .adc_dout(adc_dout),
        .sample_data(sample_data),
        .sample_valid(sample_valid),
        .sample_ready(sample_ready),
        .sample_index(sample_index),
        .frame_start(frame_start)
    );

    wire [ADC_WIDTH-1:0] fft_sample;
    wire                 fft_sample_valid;
    wire                 fft_sample_last;
    wire                 buffer_frame_available;
    reg                  start_fft_pulse;
    reg                  fft_stream_active;

    sample_buffer #(
        .DATA_WIDTH(ADC_WIDTH),
        .SAMPLE_COUNT(SAMPLE_COUNT)
    )
    u_sample_buffer (
        .clk(clk),
        .rst(rst),
        .sample_in(sample_data),
        .sample_valid(sample_valid),
        .sample_ready(sample_ready),
        .frame_available(buffer_frame_available),
        .start_fft(start_fft_pulse),
        .fft_sample(fft_sample),
        .fft_valid(fft_sample_valid),
        .fft_ready(sample_ready_fft),
        .fft_last(fft_sample_last)
    );

    wire [FFT_IP_WIDTH-1:0] fft_real;
    wire [FFT_IP_WIDTH-1:0] fft_imag;
    wire                    fft_bin_valid;
    wire                    fft_bin_last;
    wire [INDEX_WIDTH-1:0]  fft_bin_index;
    wire                    sample_ready_fft;

    wire fft_ready;
    assign fft_ready = 1'b1;

    fft_engine_wrapper #(
        .INPUT_WIDTH(ADC_WIDTH),
        .FFT_POINTS(FFT_POINTS),
        .IP_DATA_WIDTH(FFT_IP_WIDTH)
    )
    u_fft_wrapper (
        .clk(clk),
        .rst(rst),
        .sample_data(fft_sample),
        .sample_valid(fft_sample_valid),
        .sample_last(fft_sample_last),
        .sample_ready(sample_ready_fft),
        .fft_real(fft_real),
        .fft_imag(fft_imag),
        .fft_valid(fft_bin_valid),
        .fft_ready(fft_ready),
        .fft_last(fft_bin_last),
        .bin_index(fft_bin_index)
    );

    wire [MAG_WIDTH-1:0] magnitude_value;
    wire                 magnitude_valid;
    wire                 magnitude_last;

    fft_magnitude #(
        .DATA_WIDTH(FFT_IP_WIDTH),
        .MAG_WIDTH(MAG_WIDTH)
    )
    u_fft_magnitude (
        .clk(clk),
        .rst(rst),
        .real_in(fft_real),
        .imag_in(fft_imag),
        .valid_in(fft_bin_valid),
        .last_in(fft_bin_last),
        .magnitude(magnitude_value),
        .valid_out(magnitude_valid),
        .last_out(magnitude_last)
    );

    reg [INDEX_WIDTH-1:0] magnitude_index_d;

    always @(posedge clk) begin
        if (rst) begin
            magnitude_index_d <= {INDEX_WIDTH{1'b0}};
        end else if (fft_bin_valid) begin
            magnitude_index_d <= fft_bin_index;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            fft_stream_active <= 1'b0;
            start_fft_pulse   <= 1'b0;
        end else begin
            start_fft_pulse <= 1'b0;
            if (!fft_stream_active && buffer_frame_available) begin
                start_fft_pulse   <= 1'b1;
                fft_stream_active <= 1'b1;
            end else if (magnitude_valid && magnitude_last) begin
                fft_stream_active <= 1'b0;
            end
        end
    end

    wire [ADC_WIDTH+3:0] amplitude_metric;
    wire [31:0]          frequency_metric;
    wire [15:0]          duty_metric;
    wire [15:0]          thd_metric;

    signal_metrics #(
        .DATA_WIDTH(ADC_WIDTH),
        .SAMPLE_COUNT(SAMPLE_COUNT),
        .SAMPLE_RATE(SAMPLE_RATE),
        .FFT_POINTS(FFT_POINTS),
        .MAG_WIDTH(MAG_WIDTH)
    )
    u_signal_metrics (
        .clk(clk),
        .rst(rst),
        .sample_data(sample_data),
        .sample_valid(sample_valid),
        .frame_start(frame_start),
        .magnitude_in(magnitude_value),
        .magnitude_valid(magnitude_valid),
        .magnitude_last(magnitude_last),
        .magnitude_index(magnitude_index_d),
        .amplitude(amplitude_metric),
        .frequency_hz(frequency_metric),
        .duty_cycle_permille(duty_metric),
        .thd_tenths_percent(thd_metric)
    );

    wire [15:0] pixel_rgb_int;
    wire        pixel_ready_int;

    display_formatter #(
        .H_RES(H_RES),
        .V_RES(V_RES),
        .FFT_POINTS(FFT_POINTS),
        .MAG_WIDTH(MAG_WIDTH),
        .DATA_WIDTH(ADC_WIDTH)
    )
    u_display_formatter (
        .clk(clk),
        .rst(rst),
        .magnitude_in(magnitude_value),
        .magnitude_valid(magnitude_valid),
        .magnitude_index(magnitude_index_d),
        .magnitude_last(magnitude_last),
        .amplitude_value(amplitude_metric),
        .frequency_hz(frequency_metric),
        .duty_cycle_permille(duty_metric),
        .thd_tenths_percent(thd_metric),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .pixel_valid(pixel_valid),
        .pixel_rgb(pixel_rgb_int),
        .pixel_ready(pixel_ready_int)
    );

    assign pixel_rgb   = pixel_rgb_int;
    assign pixel_ready = pixel_ready_int;

endmodule
