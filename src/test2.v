`timescale 1ns / 1ps

module test2 #(
    parameter integer DATAIN_WIDTH  = 16,
    parameter integer DATAOUT_WIDTH = 16,
    parameter integer FFT_POINTS    = 1024
) (
    input  wire                       i_aclk,
    input  wire                       i_axi4s_data_tvalid,
    input  wire [2*DATAIN_WIDTH-1:0]  i_axi4s_data_tdata,
    input  wire                       i_axi4s_data_tlast,
    output wire                       o_axi4s_data_tready,
    input  wire                       i_axi4s_cfg_tvalid,
    input  wire                       i_axi4s_cfg_tdata,
    output wire                       o_axi4s_data_tvalid,
    output wire [2*DATAOUT_WIDTH-1:0] o_axi4s_data_tdata,
    output wire                       o_axi4s_data_tlast,
    output wire [23:0]                o_axi4s_data_tuser,
    output wire [2:0]                 o_alm,
    output wire                       o_stat
);

    reg cfg_done;

    initial cfg_done = 1'b0;

    always @(posedge i_aclk) begin
        if (!cfg_done) begin
            if (i_axi4s_cfg_tvalid && i_axi4s_cfg_tdata) begin
                cfg_done <= 1'b1;
            end
        end
    end

    wire core_resetn = cfg_done;

    wire [DATAOUT_WIDTH-1:0] fft_input_data;
    assign fft_input_data = {{(DATAOUT_WIDTH-DATAIN_WIDTH){i_axi4s_data_tdata[DATAIN_WIDTH-1]}},
                              i_axi4s_data_tdata[DATAIN_WIDTH-1:0]};

    wire                      s_axis_tready;
    wire                      m_axis_tvalid;
    wire [2*DATAOUT_WIDTH-1:0] m_axis_tdata;
    wire                      m_axis_tlast;

    assign o_axi4s_data_tready = cfg_done ? s_axis_tready : 1'b0;

    fft_ip_core_stub #(
        .DATA_WIDTH(DATAOUT_WIDTH),
        .POINTS    (FFT_POINTS)
    ) u_fft_core (
        .aclk          (i_aclk),
        .aresetn       (core_resetn),
        .s_axis_tdata  (fft_input_data),
        .s_axis_tvalid (i_axi4s_data_tvalid && cfg_done),
        .s_axis_tready (s_axis_tready),
        .s_axis_tlast  (i_axi4s_data_tlast),
        .m_axis_tdata  (m_axis_tdata),
        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tready (1'b1),
        .m_axis_tlast  (m_axis_tlast)
    );

    assign o_axi4s_data_tvalid = m_axis_tvalid;
    assign o_axi4s_data_tdata  = m_axis_tdata;
    assign o_axi4s_data_tlast  = m_axis_tlast;
    assign o_axi4s_data_tuser  = 24'd0;
    assign o_alm               = 3'b000;
    assign o_stat              = cfg_done;

endmodule
