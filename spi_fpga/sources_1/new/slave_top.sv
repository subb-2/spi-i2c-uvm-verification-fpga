`timescale 1ns / 1ps

module slave_top (
    input  logic       clk,
    input  logic       rst,
    input  logic       scl,
    inout  wire        sda,
    output logic [3:0] fnd_digit,
    output logic [7:0] fnd_data
);

    logic [7:0] s_tx_data;
    logic [7:0] s_rx_data;
    logic       s_done;
    logic [13:0] fnd_in_data;

    assign s_tx_data   = 8'h00;
    assign fnd_in_data = rst ? 14'd0 : {6'd0, s_rx_data};

    i2c_slave U_I2C_SLAVE (
        .clk    (clk),
        .rst    (rst),
        .tx_data(s_tx_data),
        .rx_data(s_rx_data),
        .done   (s_done),
        .scl    (scl),
        .sda    (sda)
    );

    fnd_controller U_FND_CONTROLLER (
        .clk        (clk),
        .reset      (rst),
        .fnd_in_data(fnd_in_data),
        .fnd_digit  (fnd_digit),
        .fnd_data   (fnd_data)
    );

endmodule
