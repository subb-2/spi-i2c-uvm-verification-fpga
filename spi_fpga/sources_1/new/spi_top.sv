`timescale 1ns / 1ps

module spi_top (
    input logic clk,
    input logic rst,
    //input  logic       cpol,
    //input  logic       cpha,
    //input  logic [7:0] clk_div,
    //input  logic [7:0] m_tx_data,
    //output logic [7:0] m_rx_data,
    //output logic       m_done,
    //output logic       m_busy,
    //input  logic [7:0] s_tx_data,
    //output logic [7:0] s_rx_data,
    //output logic       s_busy, 

    input  logic       start_btn,
    input  logic [3:0] sw,
    input  logic       btn,
    output logic [3:0] fnd_digit,
    output logic [7:0] fnd_data
);

    logic sclk;
    logic mosi, miso, cs_n;
    logic [7:0] m_tx_data;

    logic [7:0] m_rx_data;
    logic       m_done;
    logic       m_busy;
    logic [7:0] s_tx_data;
    logic [7:0] s_rx_data;
    logic       s_busy;
    logic       s_rx_done;

    logic [7:0] clk_div;
    assign clk_div = 8'd4;

    logic cpol, cpha;
    assign cpol = 0;
    assign cpha = 0;

    btn_debounce U_M_START_BTN (
        .clk  (clk),
        .reset(rst),
        .i_btn(start_btn),
        .o_btn(m_start)
    );

    btn_debounce U_BTN_DEBOUNCE (
        .clk  (clk),
        .reset(rst),
        .i_btn(btn),
        .o_btn(o_btn)
    );

    sw_data U_SW_DATA (
        .sw(sw),
        .hex_data(m_tx_data)
    );

    fnd_unit U_FND_UNIT (
        .clk(clk),
        .rst(rst),
        .btn(o_btn),
        .rx_done(s_rx_done),
        .rx_data(s_rx_data),
        .fnd_digit(fnd_digit),
        .fnd_data(fnd_data)
    );

    spi_master U_SPI_MASTER (
        .clk(clk),
        .rst(rst),
        .cpol(cpol),
        .cpha(cpha),
        .clk_div(clk_div),
        .tx_data(m_tx_data),
        .start(m_start),
        .rx_data(m_rx_data),
        .done(m_done),
        .busy(m_busy),
        .sclk(sclk),
        .mosi(mosi),
        .miso(miso),
        .cs_n(cs_n)
    );

    spi_slave U_SPI_SLAVE (
        .clk(clk),
        .rst(rst),
        .sclk(sclk),
        .mosi(mosi),
        .miso(miso),
        .busy(s_busy),
        .cs_n(cs_n),
        .tx_data(s_tx_data),
        .rx_data(s_rx_data),
        .rx_done(s_rx_done)
    );
endmodule

module sw_data (
    input  logic [3:0] sw,
    output logic [7:0] hex_data
);

    always_comb begin
        if (sw <= 4'd9) begin
            hex_data = {4'b0000, sw};
        end else begin
            hex_data = 8'h00;
        end
    end

endmodule
