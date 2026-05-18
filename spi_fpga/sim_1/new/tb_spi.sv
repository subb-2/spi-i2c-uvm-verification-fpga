`timescale 1ns / 1ps

module tb_spi ();

    logic clk, rst;
    //logic cpol, cpha;
    //logic [7:0] clk_div, tx_data, rx_data;
    //logic start, done, busy, sclk, mosi, miso, cs_n;
    logic [7:0] m_tx_data, m_rx_data, s_tx_data, s_rx_data, clk_div;
    logic m_start, m_done, m_busy;
    logic cpol, cpha;
    logic miso, mosi;
    logic       s_busy;
    logic       btn;
    logic [3:0] fnd_digit;
    logic [7:0] fnd_data;


    spi_top dut (
        .clk      (clk),
        .rst      (rst),
        .cpol     (cpol),
        .cpha     (cpha),
        .clk_div  (clk_div),
        .m_tx_data(m_tx_data),
        .m_start  (m_start),
        .m_rx_data(m_rx_data),
        .m_done   (m_done),
        .m_busy   (m_busy),
        .s_tx_data(s_tx_data),
        .s_rx_data(s_rx_data),
        .s_busy   (s_busy),
        .btn      (btn),
        .fnd_digit(fnd_digit),
        .fnd_data (fnd_data)

    );

    always #5 clk = ~clk;

    //loop 
    //assign miso = mosi;

    task spi_set_mode(logic [1:0] mode);
        {cpol, cpha} = mode;
        @(posedge clk);
    endtask  //spi_set_mode

    task spi_send_data(logic [7:0] data);
        m_tx_data = data;
        s_tx_data = data;
        m_start   = 1'b1;
        @(posedge clk);
        m_start = 1'b0;
        @(posedge clk);
        wait (m_done);
        @(posedge clk);
    endtask  //spi_send

    initial begin
        clk = 0;
        rst = 1;
        btn = 0;
        repeat (3) @(posedge clk);
        rst = 0;
        //btn = 1;
        @(posedge clk);
        clk_div = 4;  // sclk = 10MHz : (100MHz / (10MHz * 2)) - 1
        miso = 1'b0;
        @(posedge clk);

        spi_set_mode(0);
        spi_send_data(8'h55);

        spi_set_mode(0);
        spi_send_data(8'h11);

        spi_set_mode(0);
        spi_send_data(8'haa);

        spi_set_mode(0);
        spi_send_data(8'hcc);

        @(posedge clk);
        #20;
        $stop;
    end

endmodule
