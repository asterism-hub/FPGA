`timescale 1ns / 1ps

module fft_engine_wrapper #(
    parameter integer INPUT_WIDTH    = 12,
    parameter integer FFT_POINTS     = 1024,
    parameter integer IP_DATA_WIDTH  = 16
) (
    input  wire                        clk,
    input  wire                        rst,
    input  wire [INPUT_WIDTH-1:0]      sample_data,
    input  wire                        sample_valid,
    input  wire                        sample_last,
    output wire                        sample_ready,
    output reg  [IP_DATA_WIDTH-1:0]    fft_real,
    output reg  [IP_DATA_WIDTH-1:0]    fft_imag,
    output reg                         fft_valid,
    input  wire                        fft_ready,
    output reg                         fft_last,
    output reg  [$clog2(FFT_POINTS)-1:0] bin_index
);

    wire [IP_DATA_WIDTH-1:0]   s_axis_tdata;
    wire                       s_axis_tready;
    wire [2*IP_DATA_WIDTH-1:0] m_axis_tdata;
    wire                       m_axis_tvalid;
    wire                       m_axis_tready;
    wire                       m_axis_tlast;

    assign s_axis_tdata  = {{(IP_DATA_WIDTH-INPUT_WIDTH){sample_data[INPUT_WIDTH-1]}}, sample_data};
    assign sample_ready  = s_axis_tready;
    assign m_axis_tready = fft_ready;

    fft_ip_core_stub #(
        .DATA_WIDTH(IP_DATA_WIDTH),
        .POINTS(FFT_POINTS)
    )
    u_fft_core (
        .aclk(clk),
        .aresetn(~rst),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(sample_valid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(sample_last),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast)
    );

    always @(posedge clk) begin
        if (rst) begin
            fft_real   <= {IP_DATA_WIDTH{1'b0}};
            fft_imag   <= {IP_DATA_WIDTH{1'b0}};
            fft_valid  <= 1'b0;
            fft_last   <= 1'b0;
            bin_index  <= {($clog2(FFT_POINTS)){1'b0}};
        end else begin
            if (m_axis_tvalid && m_axis_tready) begin
                fft_real  <= m_axis_tdata[2*IP_DATA_WIDTH-1:IP_DATA_WIDTH];
                fft_imag  <= m_axis_tdata[IP_DATA_WIDTH-1:0];
                fft_valid <= 1'b1;
                fft_last  <= m_axis_tlast;

                if (m_axis_tlast) begin
                    bin_index <= {($clog2(FFT_POINTS)){1'b0}};
                end else begin
                    bin_index <= bin_index + 1'b1;
                end
            end else if (fft_ready) begin
                fft_valid <= 1'b0;
                fft_last  <= 1'b0;
            end

            if (!m_axis_tvalid) begin
                fft_valid <= 1'b0;
            end
        end
    end

endmodule
