`timescale 1ns / 1ps

module tb_final ();

    logic       clk;
    logic       rst;
    logic       start_btn;
    logic [3:0] sw;
    logic       btn;
    logic [3:0] fnd_digit;
    logic [7:0] fnd_data;

    spi_top dut (
        .clk(clk),
        .rst(rst),
        .start_btn(start_btn),
        .sw(sw),
        .btn(btn),
        .fnd_digit(fnd_digit),
        .fnd_data(fnd_data)
    );
    
    always #5 clk = ~clk;

    initial begin
        clk   = 0;
        rst   = 1;
        btn  = 0;
        start_btn  = 0;
        sw[0] = 0;
        sw[1] = 0;
        sw[2] = 0;
        sw[3] = 0;
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        rst = 0;
        @(posedge clk);
        @(posedge clk);
        //clk_div = 4;

        sw[0] = 0;
        sw[1] = 0;
        sw[2] = 1;
        sw[3] = 0;

        btn = 1;
        #9000;
        btn = 0;
        #100;
        start_btn = 1;
        #9000;
        start_btn = 0;

        btn = 1;
        #9000;
        btn  = 0;

        sw[0] = 0;
        sw[1] = 0;
        sw[2] = 1;
        sw[3] = 1;

        start_btn  = 1;
        #9000;
        start_btn = 0;
        $stop;
    end

endmodule
