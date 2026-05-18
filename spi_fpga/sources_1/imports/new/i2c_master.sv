`timescale 1ns / 1ps

module I2C_Master_top (
    input  logic       clk,
    input  logic       rst,
    // command port 
    input  logic       cmd_start,
    input  logic       cmd_write,
    input  logic       cmd_read,
    input  logic       cmd_stop,
    input  logic [7:0] tx_data,
    input  logic       ack_in,     //master가 받는 것
    // internal output
    output logic [7:0] rx_data,
    output logic       done,
    output logic       ack_out,    //master가 주는 것 
    output logic       busy,
    //external i2c port
    output logic       scl,
    inout  logic       sda
);

    logic sda_o, sda_i;

    assign sda_i = sda;
    assign sda   = sda_o ? 1'bz : 1'b0;

    i2c_master U_I2C_TOP (
        .*,
        .sda_o(sda_o),
        .sda_i(sda_i)
    );

endmodule

module i2c_master (
    input  logic       clk,
    input  logic       rst,
    // command port 
    input  logic       cmd_start,
    input  logic       cmd_write,
    input  logic       cmd_read,
    input  logic       cmd_stop,
    input  logic [7:0] tx_data,
    input  logic       ack_in,     //master가 받는 것
    // internal output
    output logic [7:0] rx_data,
    output logic       done,
    output logic       ack_out,    //master가 주는 것 
    output logic       busy,
    //external i2c port
    output logic       scl,
    output logic       sda_o,
    input  logic       sda_i
);

    //100KHz : standard mode 
    //bit 신호를 보낼 때마다, 구간을 4개로 쪼개서 할 것임
    //실제 tick이 발생하는 속도는 400KHz로 해야 함

    typedef enum logic [2:0] {
        IDLE = 3'b000,
        START,
        WAIT_CMD,
        DATA,
        DATA_ACK,
        STOP
    } i2c_state_e;

    i2c_state_e       state;

    logic       [7:0] div_cnt;
    logic             qtr_tick;
    logic scl_r, sda_r;
    logic [1:0] step;
    logic [7:0] tx_shift_reg, rx_shift_reg;
    logic [2:0] bit_cnt;
    logic is_read, ack_in_r;

    assign scl   = scl_r;
    assign sda_o = sda_r;
    //IDLE이 아니면 busy 
    assign busy  = (state != IDLE);

    //통신 속도 
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            //들어오는 clk = 100MHz
            //400MHz = {100MHz/(100KHz * 4)} - 1
            //{100_000_000 / (100_000 * 4)} - 1 = 250 - 1 = 249 
            div_cnt  <= 0;
            qtr_tick <= 1'b0;
        end else begin
            if (div_cnt == (250 - 1)) begin  // scl : 100kHz 
                div_cnt  <= 0;
                qtr_tick <= 1'b1;
            end else begin
                div_cnt  <= div_cnt + 1;
                qtr_tick <= 1'b0;
            end
        end
    end


    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state        <= IDLE;
            scl_r        <= 1'b1;
            sda_r        <= 1'b1;
            //busy         <= 1'b0;
            step         <= 0;
            done         <= 1'b0;
            tx_shift_reg <= 0;
            rx_shift_reg <= 0;
            is_read      <= 1'b0;
            bit_cnt      <= 0;
            ack_in_r     <= 1'b1;  //nack 상태 
        end else begin
            done <= 1'b0;
            case (state)
                IDLE: begin
                    scl_r <= 1'b1;
                    sda_r <= 1'b1;
                    //busy  <= 1'b0;
                    if (cmd_start) begin
                        state <= START;
                        step  <= 0;  //한 주기를 4로 나눈 step 
                        //stop에서 idle로 넘어갈 때, 0으로 줘야하는가?
                        //위에서 assign으로 주는 것으로 변경 
                        //stop일 때 0으로 주는 것도 괜찮을거 같다고?
                        //busy  <= 1'b1; 
                    end
                end
                START: begin
                    if (qtr_tick) begin
                        case (step)
                            2'd0: begin
                                sda_r <= 1'b1;
                                scl_r <= 1'b1;
                                step  <= 2'd1;
                            end
                            2'd1: begin
                                sda_r <= 1'b0;
                                step  <= 2'd2;
                            end
                            2'd2: begin
                                //현 상태 유지 
                                step <= 2'd3;
                            end
                            2'd3: begin
                                scl_r <= 1'b0;
                                step  <= 2'd0;
                                //start 구간 끝났다는 의미 
                                done  <= 1'b1;
                                state <= WAIT_CMD;
                            end
                        endcase
                    end
                end
                WAIT_CMD: begin
                    step <= 0;
                    if (cmd_write) begin
                        //write이면, tx_data를 shift reg에 저장
                        tx_shift_reg <= tx_data;
                        bit_cnt <= 0;
                        is_read <= 1'b0;
                        state <= DATA;
                    end else if (cmd_read) begin
                        rx_shift_reg <= 0;
                        bit_cnt <= 0;
                        is_read <= 1'b1;
                        ack_in_r <= ack_in; //ack 넣어주고 이후에 전송 
                        state <= DATA;
                    end else if (cmd_stop) begin
                        state <= STOP;
                    end else if (cmd_start) begin
                        state <= START;
                    end
                end
                DATA: begin
                    if (qtr_tick) begin
                        //이 동작을 8번 반복해야 됨 
                        case (step)
                            2'd0: begin
                                //전송 
                                scl_r <= 1'b0;
                                //sda_r에 넣어야지 전송 
                                //입력값이 들어올 때 나가면 안됨
                                //sda_o = sda_r 
                                sda_r <= is_read ? 1'b1 : tx_shift_reg[7];
                                step  <= 2'd1;
                            end
                            2'd1: begin
                                // scl 상승 구간 
                                scl_r <= 1'b1;
                                step  <= 2'd2;

                            end
                            2'd2: begin
                                //수신 
                                scl_r <= 1'b1;
                                //read일 때 읽겠다.
                                if (is_read) begin
                                    rx_shift_reg <= {rx_shift_reg[6:0], sda_i};
                                end
                                step <= 2'd3;
                            end
                            2'd3: begin
                                //shift
                                scl_r <= 1'b0;
                                //read 아닐 때, write 상태일 때 shift 
                                //다음 비트 준비 
                                if (!is_read) begin
                                    tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                                end
                                step <= 2'd0;

                                if (bit_cnt == 7) begin
                                    //여기서 다시 0으로 초기화 안 해줘도 되나?
                                    state <= DATA_ACK;
                                end else begin
                                    bit_cnt <= bit_cnt + 1;
                                end
                            end
                        endcase
                    end
                end
                DATA_ACK: begin
                    //master 입장에서
                    //ack 주고, 받고
                    //nack를 줌 
                    //read, write를 먼저 판단 
                    //ack_in -> 0: ack / 1: nack 
                    //이 신호를 host 쪽에서 주는 것 
                    //cpu가 넣어주는 것 (코딩해서)
                    //받은 값은 ack_out을 통해서 host로 주는 것 
                    //**ack를 host 쪽에서 판단 
                    if (qtr_tick) begin
                        case (step)
                            2'd0: begin
                                scl_r <= 1'b0;
                                //master는 1번 구간에서 보냄
                                if (is_read) begin
                                    //latching
                                    //들어온 것을 reg에 넣어두기
                                    //들어오고 다음 명령어로 넘어갈 수 있기 때문 
                                    sda_r <= ack_in_r;
                                end else begin
                                    //ack 읽어야 함
                                    //1이면 왜 input인지는 회로 보면 알게 됨 
                                    //high impedence로 만들어줘야 ack 읽을 수 있음 
                                    sda_r <= 1'b1;  // sda input 설정 , sda high impedence 설정 
                                end
                                step <= 2'd1;
                            end
                            2'd1: begin
                                scl_r <= 1'b1;
                                step  <= 2'd2;
                            end
                            2'd2: begin
                                //ack는 3번째에서 받는게 좋음
                                scl_r <= 1'b1;
                                if (!is_read) begin  // ack 수신 
                                    //data 들어온 갑으로 나감 
                                    //host에게 알려주는 것 
                                    ack_out <= sda_i;
                                end
                                if (is_read) begin
                                    //read 입장에서 ack는 한 byte 받았다는 의미
                                    //한 바이트를 host 쪽으로 주기 
                                    rx_data <= rx_shift_reg;
                                end
                                step <= 2'd3;

                            end
                            2'd3: begin
                                scl_r <= 1'b0;
                                //신호를 받고 host가 다음을 어떻게 할지 알아서 결정 
                                done  <= 1'b1;
                                step  <= 2'd0;
                                state <= WAIT_CMD;
                            end
                        endcase
                    end
                end
                STOP: begin
                    if (qtr_tick) begin
                        case (step)
                            2'd0: begin
                                sda_r <= 1'b0;
                                scl_r <= 1'b0;
                                step  <= 2'd1;
                            end
                            2'd1: begin
                                scl_r <= 1'b1;
                                step  <= 2'd2;
                            end
                            2'd2: begin
                                sda_r <= 1'b1;
                                step  <= 2'd3;
                            end
                            2'd3: begin
                                step  <= 2'd0;
                                done  <= 1'b1;
                                state <= IDLE;
                            end
                        endcase
                    end
                end
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
