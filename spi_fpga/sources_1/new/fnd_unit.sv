`timescale 1ns / 1ps

module fnd_unit (
    input  logic       clk,
    input  logic       rst,
    input  logic       btn,
    input  logic       rx_done,
    input  logic [7:0] rx_data,
    output logic [3:0] fnd_digit,
    output       [7:0] fnd_data
);

    logic o_btn;
    logic [1:0] counter;
    logic [7:0] odata;

    mem U_MEM (
        .clk    (clk),
        .rx_done(rx_done),
        .addr   (counter),
        .idata  (rx_data),
        .odata  (odata)
    );

    btn_counter U_BTN_COUNTER (
        .clk    (clk),
        .rst    (rst),
        .btn    (btn),
        .counter(counter)
    );

    decoder_2x4 U_DECODER (
        .digit_sel  (counter),
        .fnd_digit_D(fnd_digit)
    );

    //clk_div U_CLK_DIV (
    //    .clk   (clk),
    //    .rst   (rst),
    //    .o_1khz(o_1khz)
    //);

    bcd U_BCD (
        .bcd     (odata[3:0]),
        .fnd_data(fnd_data)  //always output always Reg
    );

endmodule

module mem (
    input  logic       clk,
    input  logic       rst,
    input  logic       rx_done,
    input  logic [1:0] addr,
    input  logic [7:0] idata,
    output logic [7:0] odata
);

    logic [7:0] mem[0:3];

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            for (int i = 0; i < 4; i++) begin
                mem[i] <= 0;
            end
        end else begin
            if (rx_done) begin
                mem[addr] <= idata;
            end
        end
    end

    assign odata = mem[addr];

endmodule

module btn_counter (
    input  logic       clk,
    input  logic       rst,
    input  logic       btn,
    output logic [1:0] counter
);

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            counter <= 0;
        end else begin
            if (btn) begin
                if (counter == 3) begin
                    counter <= 0;
                end else begin
                    counter <= counter + 1;
                end
            end
        end
    end

endmodule

//to select to fnd digit display
module decoder_2x4 (
    input  logic [1:0] digit_sel,   //버튼 역할 
    output logic [3:0] fnd_digit_D
);

    always_ff @(digit_sel) begin
        case (digit_sel)
            2'b00: fnd_digit_D = 4'b1110;
            2'b01: fnd_digit_D = 4'b1101;
            2'b10: fnd_digit_D = 4'b1011;
            2'b11: fnd_digit_D = 4'b0111;
        endcase
    end

endmodule

module clk_div (
    input  logic clk,
    input  logic rst,
    output logic o_1khz
);

    logic [$clog2(100_000):0] counter_r;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            counter_r <= 0;
            o_1khz <= 1'b0;
        end else begin
            if (counter_r == 99999) begin
                counter_r <= 0;
                o_1khz <= 1'b1;
            end else begin
                counter_r <= counter_r + 1;
                o_1khz <= 1'b0;
            end
        end
    end

endmodule

module btn_debounce (
    input  clk,
    input  reset,
    input  i_btn,
    output o_btn
);

    parameter CLK_DIV = 100_0000;
    parameter F_COUNT = 100_000_000 / CLK_DIV;
    reg [$clog2(F_COUNT)-1:0] counter_reg;
    reg clk_100khz_reg;

    always @(posedge clk, posedge reset) begin
        if (reset) begin
            counter_reg <= 0;
            clk_100khz_reg <= 1'b0;
        end else begin
            counter_reg <= counter_reg + 1;
            if (counter_reg == (F_COUNT - 1)) begin
                counter_reg <= 0;
                clk_100khz_reg <= 1'b1;
            end else begin
                clk_100khz_reg <= 1'b0;
            end
        end
    end

    reg [7:0] q_reg, q_next;
    wire debounce;

    always @(posedge clk_100khz_reg, posedge reset) begin
        if (reset) begin
            q_reg <= 0;
        end else begin
            q_reg <= q_next;  //출력은 q_reg
        end
    end

    //next CL
    always @(*) begin
        q_next = {i_btn, q_reg[7:1]};
    end

    //debounce 8input AND
    assign debounce = &q_reg;

    reg edge_reg;
    //edge detection
    always @(posedge clk, posedge reset) begin  // edge는 100M에 하나 감
        if (reset) begin
            edge_reg <= 1'b0;
        end else begin
            edge_reg <= debounce;
        end
    end

    //여기까지 Q5 신호까지 제작함
    assign o_btn = debounce & (~edge_reg);
    //debounce는 제작 끝

endmodule

module bcd (
    input      [3:0] bcd,
    output reg [7:0] fnd_data  //always output always Reg
);

    always @(bcd) begin
        case (bcd)
            4'd0: fnd_data = 8'hC0;
            4'd1: fnd_data = 8'hf9;
            4'd2: fnd_data = 8'ha4;
            4'd3: fnd_data = 8'hb0;
            4'd4: fnd_data = 8'h99;
            4'd5: fnd_data = 8'h92;
            4'd6: fnd_data = 8'h82;
            4'd7: fnd_data = 8'hf8;
            4'd8: fnd_data = 8'h80;
            4'd9: fnd_data = 8'h90;
            default: fnd_data = 8'hFF;
        endcase
    end

endmodule




