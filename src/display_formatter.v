`timescale 1ns / 1ps

module display_formatter #(
    parameter integer H_RES       = 640,
    parameter integer V_RES       = 480,
    parameter integer FFT_POINTS  = 1024,
    parameter integer MAG_WIDTH   = 24,
    parameter integer DATA_WIDTH  = 12
) (
    input  wire                          clk,
    input  wire                          rst,
    input  wire [MAG_WIDTH-1:0]          magnitude_in,
    input  wire                          magnitude_valid,
    input  wire [$clog2(FFT_POINTS)-1:0] magnitude_index,
    input  wire                          magnitude_last,
    input  wire [DATA_WIDTH+3:0]         amplitude_value,
    input  wire [31:0]                   frequency_hz,
    input  wire [15:0]                   duty_cycle_permille,
    input  wire [15:0]                   thd_tenths_percent,
    input  wire [11:0]                   pixel_x,
    input  wire [11:0]                   pixel_y,
    input  wire                          pixel_valid,
    output reg  [15:0]                   pixel_rgb,
    output reg                           pixel_ready
);

    localparam integer FFT_ADDR_WIDTH = $clog2(FFT_POINTS);
    localparam integer FONT_WIDTH     = 5;
    localparam integer FONT_HEIGHT    = 7;
    localparam integer CHAR_SPACING   = 6;
    localparam integer ROW_HEIGHT     = 8;
    localparam integer TEXT_ROWS      = 4;

    reg [MAG_WIDTH-1:0] spectrum_buffer [0:FFT_POINTS-1];

    reg [31:0] amplitude_chars_vec;
    reg [47:0] frequency_chars_vec;
    reg [31:0] duty_chars_vec;
    reg [31:0] thd_chars_vec;
    reg [3:0] duty_decimal;
    reg [3:0] thd_decimal;

    function [15:0] to_bcd4;
        input [15:0] value;
        integer tmp;
        integer idx;
        reg [3:0] digit;
        reg [15:0] result;
        begin
            tmp = value;
            result = 16'd0;
            for (idx = 0; idx < 4; idx = idx + 1) begin
                digit = tmp % 10;
                result[idx*4 +: 4] = digit;
                tmp = tmp / 10;
            end
            to_bcd4 = result;
        end
    endfunction

    function [23:0] to_bcd6;
        input [31:0] value;
        integer tmp;
        integer idx;
        reg [3:0] digit;
        reg [23:0] result;
        begin
            tmp = value;
            result = 24'd0;
            for (idx = 0; idx < 6; idx = idx + 1) begin
                digit = tmp % 10;
                result[idx*4 +: 4] = digit;
                tmp = tmp / 10;
            end
            to_bcd6 = result;
        end
    endfunction

    function [31:0] format_digits4;
        input [15:0] bcd_digits;
        integer idx;
        reg leading;
        reg [7:0] ch;
        reg [31:0] result;
        reg [3:0] digit;
        begin
            leading = 1'b1;
            result  = 32'd0;
            for (idx = 0; idx < 4; idx = idx + 1) begin
                digit = bcd_digits[(3-idx)*4 +: 4];
                if (leading && (digit == 0) && (idx != 3)) begin
                    ch = " ";
                end else begin
                    leading = 1'b0;
                    ch = "0" + digit;
                end
                if ((idx == 3) && leading) begin
                    ch = "0";
                    leading = 1'b0;
                end
                result = {result[23:0], ch};
            end
            format_digits4 = result;
        end
    endfunction

    function [47:0] format_digits6;
        input [23:0] bcd_digits;
        integer idx;
        reg leading;
        reg [7:0] ch;
        reg [47:0] result;
        reg [3:0] digit;
        begin
            leading = 1'b1;
            result  = 48'd0;
            for (idx = 0; idx < 6; idx = idx + 1) begin
                digit = bcd_digits[(5-idx)*4 +: 4];
                if (leading && (digit == 0) && (idx != 5)) begin
                    ch = " ";
                end else begin
                    leading = 1'b0;
                    ch = "0" + digit;
                end
                if ((idx == 5) && leading) begin
                    ch = "0";
                    leading = 1'b0;
                end
                result = {result[39:0], ch};
            end
            format_digits6 = result;
        end
    endfunction

    function [7:0] get_char4;
        input [31:0] vec;
        input [1:0]  index;
        begin
            case (index)
                2'd0: get_char4 = vec[31:24];
                2'd1: get_char4 = vec[23:16];
                2'd2: get_char4 = vec[15:8];
                2'd3: get_char4 = vec[7:0];
                default: get_char4 = 8'h20;
            endcase
        end
    endfunction

    function [7:0] get_char6;
        input [47:0] vec;
        input [3:0]  index;
        begin
            case (index)
                4'd0: get_char6 = vec[47:40];
                4'd1: get_char6 = vec[39:32];
                4'd2: get_char6 = vec[31:24];
                4'd3: get_char6 = vec[23:16];
                4'd4: get_char6 = vec[15:8];
                4'd5: get_char6 = vec[7:0];
                default: get_char6 = 8'h20;
            endcase
        end
    endfunction

    function [4:0] glyph_row;
        input [7:0] char_code;
        input [2:0] row_idx;
        begin
            case (char_code)
                "0": case (row_idx)
                    0: glyph_row = 5'b11111;
                    1: glyph_row = 5'b10001;
                    2: glyph_row = 5'b10101;
                    3: glyph_row = 5'b10101;
                    4: glyph_row = 5'b10001;
                    5: glyph_row = 5'b10001;
                    default: glyph_row = 5'b11111;
                endcase
                "1": case (row_idx)
                    0: glyph_row = 5'b00100;
                    1: glyph_row = 5'b01100;
                    2: glyph_row = 5'b00100;
                    3: glyph_row = 5'b00100;
                    4: glyph_row = 5'b00100;
                    5: glyph_row = 5'b00100;
                    default: glyph_row = 5'b01110;
                endcase
                "2": case (row_idx)
                    0: glyph_row = 5'b11110;
                    1: glyph_row = 5'b00001;
                    2: glyph_row = 5'b00010;
                    3: glyph_row = 5'b00100;
                    4: glyph_row = 5'b01000;
                    5: glyph_row = 5'b10000;
                    default: glyph_row = 5'b11111;
                endcase
                "3": case (row_idx)
                    0: glyph_row = 5'b11110;
                    1: glyph_row = 5'b00001;
                    2: glyph_row = 5'b00110;
                    3: glyph_row = 5'b00001;
                    4: glyph_row = 5'b00001;
                    5: glyph_row = 5'b10001;
                    default: glyph_row = 5'b01110;
                endcase
                "4": case (row_idx)
                    0: glyph_row = 5'b00010;
                    1: glyph_row = 5'b00110;
                    2: glyph_row = 5'b01010;
                    3: glyph_row = 5'b11111;
                    4: glyph_row = 5'b00010;
                    5: glyph_row = 5'b00010;
                    default: glyph_row = 5'b00010;
                endcase
                "5": case (row_idx)
                    0: glyph_row = 5'b11111;
                    1: glyph_row = 5'b10000;
                    2: glyph_row = 5'b11110;
                    3: glyph_row = 5'b00001;
                    4: glyph_row = 5'b00001;
                    5: glyph_row = 5'b10001;
                    default: glyph_row = 5'b01110;
                endcase
                "6": case (row_idx)
                    0: glyph_row = 5'b01110;
                    1: glyph_row = 5'b10000;
                    2: glyph_row = 5'b11110;
                    3: glyph_row = 5'b10001;
                    4: glyph_row = 5'b10001;
                    5: glyph_row = 5'b10001;
                    default: glyph_row = 5'b01110;
                endcase
                "7": case (row_idx)
                    0: glyph_row = 5'b11111;
                    1: glyph_row = 5'b00010;
                    2: glyph_row = 5'b00100;
                    3: glyph_row = 5'b01000;
                    4: glyph_row = 5'b10000;
                    5: glyph_row = 5'b10000;
                    default: glyph_row = 5'b10000;
                endcase
                "8": case (row_idx)
                    0: glyph_row = 5'b01110;
                    1: glyph_row = 5'b10001;
                    2: glyph_row = 5'b01110;
                    3: glyph_row = 5'b10001;
                    4: glyph_row = 5'b10001;
                    5: glyph_row = 5'b10001;
                    default: glyph_row = 5'b01110;
                endcase
                "9": case (row_idx)
                    0: glyph_row = 5'b01110;
                    1: glyph_row = 5'b10001;
                    2: glyph_row = 5'b10001;
                    3: glyph_row = 5'b01111;
                    4: glyph_row = 5'b00001;
                    5: glyph_row = 5'b00010;
                    default: glyph_row = 5'b11100;
                endcase
                "A": case (row_idx)
                    0: glyph_row = 5'b01110;
                    1: glyph_row = 5'b10001;
                    2: glyph_row = 5'b11111;
                    3: glyph_row = 5'b10001;
                    4: glyph_row = 5'b10001;
                    5: glyph_row = 5'b10001;
                    default: glyph_row = 5'b10001;
                endcase
                "M": case (row_idx)
                    0: glyph_row = 5'b10001;
                    1: glyph_row = 5'b11011;
                    2: glyph_row = 5'b10101;
                    3: glyph_row = 5'b10101;
                    4: glyph_row = 5'b10001;
                    5: glyph_row = 5'b10001;
                    default: glyph_row = 5'b10001;
                endcase
                "P": case (row_idx)
                    0: glyph_row = 5'b11110;
                    1: glyph_row = 5'b10001;
                    2: glyph_row = 5'b11110;
                    3: glyph_row = 5'b10000;
                    4: glyph_row = 5'b10000;
                    5: glyph_row = 5'b10000;
                    default: glyph_row = 5'b10000;
                endcase
                "F": case (row_idx)
                    0: glyph_row = 5'b11111;
                    1: glyph_row = 5'b10000;
                    2: glyph_row = 5'b11110;
                    3: glyph_row = 5'b10000;
                    4: glyph_row = 5'b10000;
                    5: glyph_row = 5'b10000;
                    default: glyph_row = 5'b10000;
                endcase
                "R": case (row_idx)
                    0: glyph_row = 5'b11110;
                    1: glyph_row = 5'b10001;
                    2: glyph_row = 5'b11110;
                    3: glyph_row = 5'b10100;
                    4: glyph_row = 5'b10010;
                    5: glyph_row = 5'b10001;
                    default: glyph_row = 5'b10001;
                endcase
                "E": case (row_idx)
                    0: glyph_row = 5'b11111;
                    1: glyph_row = 5'b10000;
                    2: glyph_row = 5'b11110;
                    3: glyph_row = 5'b10000;
                    4: glyph_row = 5'b10000;
                    5: glyph_row = 5'b11111;
                    default: glyph_row = 5'b10000;
                endcase
                "Q": case (row_idx)
                    0: glyph_row = 5'b01110;
                    1: glyph_row = 5'b10001;
                    2: glyph_row = 5'b10001;
                    3: glyph_row = 5'b10001;
                    4: glyph_row = 5'b10101;
                    5: glyph_row = 5'b10010;
                    default: glyph_row = 5'b01101;
                endcase
                "D": case (row_idx)
                    0: glyph_row = 5'b11110;
                    1: glyph_row = 5'b10001;
                    2: glyph_row = 5'b10001;
                    3: glyph_row = 5'b10001;
                    4: glyph_row = 5'b10001;
                    5: glyph_row = 5'b11110;
                    default: glyph_row = 5'b00000;
                endcase
                "U": case (row_idx)
                    0: glyph_row = 5'b10001;
                    1: glyph_row = 5'b10001;
                    2: glyph_row = 5'b10001;
                    3: glyph_row = 5'b10001;
                    4: glyph_row = 5'b10001;
                    5: glyph_row = 5'b01110;
                    default: glyph_row = 5'b00000;
                endcase
                "T": case (row_idx)
                    0: glyph_row = 5'b11111;
                    1: glyph_row = 5'b00100;
                    2: glyph_row = 5'b00100;
                    3: glyph_row = 5'b00100;
                    4: glyph_row = 5'b00100;
                    5: glyph_row = 5'b00100;
                    default: glyph_row = 5'b00100;
                endcase
                "Y": case (row_idx)
                    0: glyph_row = 5'b10001;
                    1: glyph_row = 5'b10001;
                    2: glyph_row = 5'b01010;
                    3: glyph_row = 5'b00100;
                    4: glyph_row = 5'b00100;
                    5: glyph_row = 5'b00100;
                    default: glyph_row = 5'b00100;
                endcase
                "H": case (row_idx)
                    0: glyph_row = 5'b10001;
                    1: glyph_row = 5'b10001;
                    2: glyph_row = 5'b11111;
                    3: glyph_row = 5'b10001;
                    4: glyph_row = 5'b10001;
                    5: glyph_row = 5'b10001;
                    default: glyph_row = 5'b00000;
                endcase
                "Z": case (row_idx)
                    0: glyph_row = 5'b11111;
                    1: glyph_row = 5'b00010;
                    2: glyph_row = 5'b00100;
                    3: glyph_row = 5'b01000;
                    4: glyph_row = 5'b10000;
                    5: glyph_row = 5'b11111;
                    default: glyph_row = 5'b00000;
                endcase
                "%": case (row_idx)
                    0: glyph_row = 5'b10001;
                    1: glyph_row = 5'b00010;
                    2: glyph_row = 5'b00100;
                    3: glyph_row = 5'b01000;
                    4: glyph_row = 5'b10000;
                    5: glyph_row = 5'b10001;
                    default: glyph_row = 5'b00100;
                endcase
                ":": case (row_idx)
                    0: glyph_row = 5'b00000;
                    1: glyph_row = 5'b00100;
                    2: glyph_row = 5'b00000;
                    3: glyph_row = 5'b00000;
                    4: glyph_row = 5'b00100;
                    5: glyph_row = 5'b00000;
                    default: glyph_row = 5'b00000;
                endcase
                ".": case (row_idx)
                    0: glyph_row = 5'b00000;
                    1: glyph_row = 5'b00000;
                    2: glyph_row = 5'b00000;
                    3: glyph_row = 5'b00000;
                    4: glyph_row = 5'b00100;
                    5: glyph_row = 5'b00000;
                    default: glyph_row = 5'b00000;
                endcase
                default: glyph_row = 5'b00000;
            endcase
        end
    endfunction

    integer idx;

    always @(posedge clk) begin
        if (rst) begin
            for (idx = 0; idx < FFT_POINTS; idx = idx + 1) begin
                spectrum_buffer[idx] <= {MAG_WIDTH{1'b0}};
            end
            amplitude_chars_vec <= format_digits4(16'd0);
            frequency_chars_vec <= format_digits6(24'd0);
            duty_chars_vec      <= format_digits4(16'd0);
            thd_chars_vec       <= format_digits4(16'd0);
            duty_decimal        <= 4'd0;
            thd_decimal         <= 4'd0;
        end else begin
            if (magnitude_valid) begin
                spectrum_buffer[magnitude_index] <= magnitude_in;
            end

            if (magnitude_valid && magnitude_last) begin
                amplitude_chars_vec <= format_digits4(to_bcd4(amplitude_value[15:0]));
                frequency_chars_vec <= format_digits6(to_bcd6(frequency_hz));
                duty_chars_vec      <= format_digits4(to_bcd4((duty_cycle_permille / 10))); 
                thd_chars_vec       <= format_digits4(to_bcd4((thd_tenths_percent / 10)));
                duty_decimal        <= duty_cycle_permille % 10;
                thd_decimal         <= thd_tenths_percent % 10;
            end
        end
    end

    wire [15:0] bar_area_height = V_RES - (TEXT_ROWS * ROW_HEIGHT);
    wire [FFT_ADDR_WIDTH-1:0] pixel_bin = (pixel_x * FFT_POINTS) / H_RES;
    wire [MAG_WIDTH-1:0] bin_value = spectrum_buffer[pixel_bin];
    wire [15:0] scaled_magnitude = (MAG_WIDTH > 10) ? (bin_value >> (MAG_WIDTH-10)) : bin_value;
    wire [15:0] bar_height = (scaled_magnitude * bar_area_height) >> 10;
    wire [15:0] bar_threshold = (TEXT_ROWS * ROW_HEIGHT) + (bar_area_height - bar_height);

    reg [7:0] current_char;
    reg [2:0] font_row_idx;
    reg [2:0] font_col_idx;
    reg       glyph_pixel_on;

    always @(*) begin
        pixel_ready = pixel_valid;
        pixel_rgb   = 16'h0000;
        glyph_pixel_on = 1'b0;

        if (!pixel_valid) begin
            pixel_rgb = 16'h0000;
        end else if (pixel_y < TEXT_ROWS * ROW_HEIGHT) begin
            integer text_row;
            integer char_pos;
            text_row = pixel_y / ROW_HEIGHT;
            font_row_idx = pixel_y % ROW_HEIGHT;
            char_pos = pixel_x / CHAR_SPACING;
            font_col_idx = pixel_x % CHAR_SPACING;

            if ((font_row_idx < FONT_HEIGHT) && (font_col_idx < FONT_WIDTH)) begin
                case (text_row)
                    0: begin
                        case (char_pos)
                            0: current_char = "A";
                            1: current_char = "M";
                            2: current_char = "P";
                            3: current_char = ":";
                            4: current_char = get_char4(amplitude_chars_vec, 2'd0);
                            5: current_char = get_char4(amplitude_chars_vec, 2'd1);
                            6: current_char = get_char4(amplitude_chars_vec, 2'd2);
                            7: current_char = get_char4(amplitude_chars_vec, 2'd3);
                            default: current_char = " ";
                        endcase
                    end
                    1: begin
                        case (char_pos)
                            0: current_char = "F";
                            1: current_char = "R";
                            2: current_char = "E";
                            3: current_char = "Q";
                            4: current_char = ":";
                            5: current_char = get_char6(frequency_chars_vec, 4'd0);
                            6: current_char = get_char6(frequency_chars_vec, 4'd1);
                            7: current_char = get_char6(frequency_chars_vec, 4'd2);
                            8: current_char = get_char6(frequency_chars_vec, 4'd3);
                            9: current_char = get_char6(frequency_chars_vec, 4'd4);
                            10: current_char = get_char6(frequency_chars_vec, 4'd5);
                            11: current_char = "H";
                            12: current_char = "Z";
                            default: current_char = " ";
                        endcase
                    end
                    2: begin
                        case (char_pos)
                            0: current_char = "D";
                            1: current_char = "U";
                            2: current_char = "T";
                            3: current_char = "Y";
                            4: current_char = ":";
                            5: current_char = get_char4(duty_chars_vec, 2'd0);
                            6: current_char = get_char4(duty_chars_vec, 2'd1);
                            7: current_char = get_char4(duty_chars_vec, 2'd2);
                            8: current_char = get_char4(duty_chars_vec, 2'd3);
                            9: current_char = ".";
                            10: current_char = "0" + duty_decimal;
                            11: current_char = "%";
                            default: current_char = " ";
                        endcase
                    end
                    3: begin
                        case (char_pos)
                            0: current_char = "T";
                            1: current_char = "H";
                            2: current_char = "D";
                            3: current_char = ":";
                            4: current_char = get_char4(thd_chars_vec, 2'd0);
                            5: current_char = get_char4(thd_chars_vec, 2'd1);
                            6: current_char = get_char4(thd_chars_vec, 2'd2);
                            7: current_char = get_char4(thd_chars_vec, 2'd3);
                            8: current_char = ".";
                            9: current_char = "0" + thd_decimal;
                            10: current_char = "%";
                            default: current_char = " ";
                        endcase
                    end
                    default: current_char = " ";
                endcase

                glyph_pixel_on = glyph_row(current_char, font_row_idx)[FONT_WIDTH-1-font_col_idx];
            end else begin
                glyph_pixel_on = 1'b0;
            end

            pixel_rgb = glyph_pixel_on ? 16'hFFFF : 16'h0000;
        end else begin
            if (pixel_y >= bar_threshold) begin
                pixel_rgb = 16'h07E0;
            end else begin
                pixel_rgb = 16'h0008;
            end
        end
    end

endmodule
