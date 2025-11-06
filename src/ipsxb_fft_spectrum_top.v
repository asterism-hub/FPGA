`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Top level FFT spectrum pipeline adapted for HDMI rendering
// -----------------------------------------------------------------------------
module ipsxb_fft_spectrum_top #(
    parameter integer NPOINT      = 1024,
    parameter integer INPUT_WIDTH = 8,
    parameter integer MAG_W       = 16
) (
    input  wire         i_clk,
    input  wire         i_rstn,
    input  wire         adc_clk,
    input  wire [7:0]   adc_data,
    input  wire         pix_clk,
    output wire         tmds_clk_p,
    output wire         tmds_clk_n,
    output wire [2:0]   tmds_d_p,
    output wire [2:0]   tmds_d_n
);

    localparam integer DATAIN_BYTE_NUM  = ((INPUT_WIDTH % 8) == 0) ? (INPUT_WIDTH / 8) : (INPUT_WIDTH / 8) + 1;
    localparam integer DATAIN_WIDTH     = DATAIN_BYTE_NUM * 8;
    localparam integer OUTPUT_WIDTH     = INPUT_WIDTH;
    localparam integer DATAOUT_BYTE_NUM = ((OUTPUT_WIDTH % 8) == 0) ? (OUTPUT_WIDTH / 8) : (OUTPUT_WIDTH / 8) + 1;
    localparam integer DATAOUT_WIDTH    = DATAOUT_BYTE_NUM * 8;

    wire srstn;
    ipsxb_fft_sync_arstn u_sync_arstn (
        .i_clk(i_clk),
        .i_arstn_presync(i_rstn),
        .o_arstn_synced(srstn)
    );

    wire                         s_tvalid;
    wire                         s_tready;
    wire                         s_tlast;
    wire [DATAIN_WIDTH*2-1:0]    s_tdata;

    adc_to_fft_axis #(
        .NPOINT    (NPOINT),
        .DIN_W     (DATAIN_WIDTH),
        .USE_ASYNC (0)
    ) u_feeder (
        .adc_clk  (adc_clk),
        .adc_rstn (i_rstn),
        .adc_data (adc_data),
        .sys_clk  (i_clk),
        .sys_rstn (srstn),
        .s_tvalid (s_tvalid),
        .s_tready (s_tready),
        .s_tlast  (s_tlast),
        .s_tdata  (s_tdata)
    );

    wire cfg_tvalid;
    wire cfg_tdata;
    fft_cfg_pulse u_cfg (
        .i_clk(i_clk),
        .i_rstn(srstn),
        .o_cfg_valid(cfg_tvalid),
        .o_cfg_data(cfg_tdata)
    );

    wire                      m_tvalid;
    wire                      m_tlast;
    wire [DATAOUT_WIDTH*2-1:0] m_tdata;
    wire [23:0]               m_tuser;
    wire [2:0]                alm;
    wire                      stat;

    test2 #(
        .DATAIN_WIDTH (DATAIN_WIDTH),
        .DATAOUT_WIDTH(DATAOUT_WIDTH),
        .FFT_POINTS   (NPOINT)
    ) u_fft_wrapper (
        .i_aclk              (i_clk),
        .i_axi4s_data_tvalid (s_tvalid),
        .i_axi4s_data_tdata  (s_tdata),
        .i_axi4s_data_tlast  (s_tlast),
        .o_axi4s_data_tready (s_tready),
        .i_axi4s_cfg_tvalid  (cfg_tvalid),
        .i_axi4s_cfg_tdata   (cfg_tdata),
        .o_axi4s_data_tvalid (m_tvalid),
        .o_axi4s_data_tdata  (m_tdata),
        .o_axi4s_data_tlast  (m_tlast),
        .o_axi4s_data_tuser  (m_tuser),
        .o_alm               (alm),
        .o_stat              (stat)
    );

    wire [($clog2(NPOINT/2))-1:0] ram_addr_a;
    wire [MAG_W-1:0]              ram_din_a;
    wire                          ram_we_a;

    wire signed [DATAOUT_WIDTH-1:0] xk_re = m_tdata[DATAOUT_WIDTH-1:0];
    wire signed [DATAOUT_WIDTH-1:0] xk_im = m_tdata[2*DATAOUT_WIDTH-1:DATAOUT_WIDTH];

    fft_mag_store #(
        .NPOINT (NPOINT),
        .DOUT_W (DATAOUT_WIDTH),
        .MAG_W  (MAG_W)
    ) u_mag (
        .sys_clk    (i_clk),
        .sys_rstn   (srstn),
        .m_tvalid   (m_tvalid),
        .m_tlast    (m_tlast),
        .m_tdata_re (xk_re),
        .m_tdata_im (xk_im),
        .ram_addr_a (ram_addr_a),
        .ram_din_a  (ram_din_a),
        .ram_we_a   (ram_we_a)
    );

    wire [($clog2(NPOINT/2))-1:0] ram_addr_b;
    wire [MAG_W-1:0]              ram_dout_b;

    dpram #(
        .AW($clog2(NPOINT/2)),
        .DW(MAG_W)
    ) u_bram (
        .clka (i_clk),
        .addra(ram_addr_a),
        .dina (ram_din_a),
        .wea  (ram_we_a),
        .clkb (pix_clk),
        .addrb(ram_addr_b),
        .doutb(ram_dout_b)
    );

    wire [11:0] x;
    wire [11:0] y;
    wire        de;
    wire        hsync;
    wire        vsync;
    wire [7:0]  R;
    wire [7:0]  G;
    wire [7:0]  B;

    vt_720p u_vtim (
        .pix_clk(pix_clk),
        .rstn(i_rstn),
        .x(x),
        .y(y),
        .de(de),
        .hsync(hsync),
        .vsync(vsync)
    );

    spectrum_renderer #(
        .NPOINT(NPOINT),
        .MAG_W(MAG_W)
    ) u_draw (
        .pix_clk   (pix_clk),
        .rstn      (i_rstn),
        .x         (x),
        .y         (y),
        .de        (de),
        .ram_addr_b(ram_addr_b),
        .ram_dout_b(ram_dout_b),
        .r         (R),
        .g         (G),
        .b         (B)
    );

    hdmi_tx u_tx (
        .pix_clk   (pix_clk),
        .de        (de),
        .hsync     (hsync),
        .vsync     (vsync),
        .red       (R),
        .green     (G),
        .blue      (B),
        .tmds_clk_p(tmds_clk_p),
        .tmds_clk_n(tmds_clk_n),
        .tmds_d_p  (tmds_d_p),
        .tmds_d_n  (tmds_d_n)
    );

endmodule
