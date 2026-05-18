`timescale 1ns / 1ps

module i2c_slave (
    input  logic       clk,
    input  logic       rst,
    input  logic [7:0] tx_data,  // fnd로 
    //input  logic       ack_in,      // master가 주는 것, slave가 받는 것 
    // internal output
    output logic [7:0] rx_data,  // fnd로 
    output logic       done,     // fnd로 
    //output logic       ack_out,     // master가 받는 것, slave가 주는 것 
    //output logic       busy,     // fnd로 
    // to master 
    input  logic       scl,
    inout  logic       sda
);

    localparam SLAVE_ADDR = 7'h12;

    // 3state buf ===============================
    logic sda_o, sda_i;

    assign sda_i = sda;
    assign sda   = sda_o ? 1'bz : 1'b0;

    // edge  scl ===================================
    logic scl_edge_reg, scl_edge_rise, scl_edge_falling;

    assign scl_edge_rise    = (~scl_edge_reg) & scl;
    assign scl_edge_falling = scl_edge_reg & (~scl);

    //edge detector
    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            scl_edge_reg <= 1;
        end else begin
            scl_edge_reg <= scl;  // 현재 sclk 값 
        end
    end
    // ===========================================

    // edge  sda ===================================
    logic sda_edge_reg, sda_rise, sda_falling;

    assign sda_rise    = (~sda_edge_reg) & sda_i;
    assign sda_falling = sda_edge_reg & (~sda_i);

    //edge detector
    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            sda_edge_reg <= 1;
        end else begin
            sda_edge_reg <= sda_i;  // 현재 sclk 값 
        end
    end
    // ===========================================

    //100KHz : standard mode 
    //bit 신호를 보낼 때마다, 구간을 4개로 쪼개서 할 것임
    //실제 tick이 발생하는 속도는 400KHz로 해야 함

    typedef enum logic [2:0] {
        IDLE,
        ADDR,
        WRITE_DATA,
        READ_DATA,
        DATA_ACK,
        STOP
    } i2c_state_e;

    i2c_state_e state;

    logic scl_r, sda_r;
    logic [1:0] step;
    logic [7:0] tx_shift_reg, rx_shift_reg;
    logic [3:0] bit_cnt;
    logic ack_in_r;

    logic [6:0] fnd_slave_addr;

    logic bef_read, bef_write;
    logic from_addr;  // ADDR에서 온 경우 구분

    //assign scl   = scl_r;
    assign sda_o = sda_r;

    //IDLE이 아니면 busy 
    assign busy  = (state != IDLE);

    //scl count 
    //    always_ff @(posedge clk, posedge rst) begin
    //        if (rst) begin
    //            bit_cnt <= 0;
    //        end else begin
    //            if (scl_edge_rise) begin
    //                bit_cnt <= bit_cnt + 1;
    //            end
    //        end
    //    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state          <= IDLE;
            fnd_slave_addr <= 7'b0010010;
            sda_r          <= 1'b1;
            step           <= 0;
            tx_shift_reg   <= 0;
            rx_shift_reg   <= 0;
            rx_data        <= 0;
            bit_cnt        <= 0;
            done           <= 0;
            ack_in_r       <= 1'b1;  //nack 상태 
            bef_read       <= 0;
            bef_write      <= 0;
            from_addr      <= 0;
        end else begin
            done <= 1'b0;
            if (sda_rise && scl == 1'b1) begin
                step  <= 0;
                state <= IDLE;
                bit_cnt  <= 0;
                sda_r    <= 1'b1;
                bef_read <= 0;
                bef_write<= 0;
                from_addr <= 0;
            end else begin
                case (state)
                    IDLE: begin
                        case (step)
                            2'd0: begin
                                if (sda_falling) begin
                                    step <= 1;
                                end
                            end
                            2'd1: begin
                                if (scl_edge_falling) begin
                                    step  <= 0;
                                    state <= ADDR;
                                end
                            end
                        endcase
                    end
                    ADDR: begin
                        if (scl_edge_rise) begin
                            rx_shift_reg <= {rx_shift_reg[6:0], sda_i};
                        end
                        if (scl_edge_falling) begin
                            bit_cnt <= bit_cnt + 1;
                            if (bit_cnt == 7) begin //7이되고 rise가 하나 더 왔을 때 0으로 됨 
                                rx_data <= rx_shift_reg;
                                bit_cnt <= 0;
                                if (rx_shift_reg[7:1] == SLAVE_ADDR) begin
                                    sda_r <= 1'b0;
                                    from_addr <= 1'b1;
                                    if (rx_shift_reg[0] == 1'b1) begin
                                        //tx_shift_reg <= tx_data;
                                        bef_read  <= 1'b0;
                                        bef_write <= 1'b1;
                                        //state <= WRITE_DATA;
                                    end else begin
                                        bef_write <= 1'b0;
                                        bef_read  <= 1'b1;
                                    end
                                    state <= DATA_ACK;
                                end else begin
                                    sda_r <= 1'b1;
                                    state <= IDLE;
                                end
                            end
                        end
                    end
                    // bit_cnt == 7 의 rise 
                    DATA_ACK: begin
                        // write 명령을 받은 직후(slave가 ACK 보내야 하는 경우)
                        if (bef_read) begin
                            // master->slave 전송 후 slave ACK
                            sda_r <= 1'b0;  // ACK 유지
                        end else begin
                            // slave->master 전송 후 master ACK 받아야 하므로 release
                            sda_r <= 1'b1;  // release
                        end

                        if (scl_edge_rise) begin
                            if (bef_write && !from_addr) begin
                                ack_in_r <= sda_i;  // master ACK/NACK 샘플
                            end
                        end

                        if (scl_edge_falling) begin
                            bit_cnt <= 0;
                            if (bef_read) begin
                                sda_r <= 1'b1;  // ACK 끝났으니 이제 release
                                state <= READ_DATA;
                            end

                            if (bef_write) begin
                                if (from_addr) begin
                                    sda_r        <= tx_data[7];           // 첫 번째 비트를 즉시 출력
                                    tx_shift_reg <= {
                                        tx_data[6:0], 1'b0
                                    };  // 1비트 미리 시프트
                                    bit_cnt      <= 1;                    // 1비트 전송 완료 처리
                                    state <= WRITE_DATA;
                                end else begin
                                    if (ack_in_r == 1'b0) begin
                                        tx_shift_reg <= tx_data;
                                        tx_shift_reg <= {tx_data[6:0], 1'b0};
                                        sda_r <= tx_data[7];
                                        bit_cnt <= 1;
                                        done <= 1'b1;
                                        state <= WRITE_DATA;  // ACK면 계속
                                    end else begin
                                        state <= IDLE;  // NACK면 종료
                                    end
                                end
                            end
                        end
                    end

                    WRITE_DATA: begin
                        if (scl_edge_falling) begin
                            if (bit_cnt == 8) begin
                                bit_cnt <= 0;
                                sda_r   <= 1'b1;     // 마스터가 ACK를 보낼 수 있도록 SDA를 Release
                                state   <= DATA_ACK; // 8비트 전송 완료 후 ACK 대기 상태로 전환
                            end else begin
                                sda_r        <= tx_shift_reg[7];           // 다음 비트 출력
                                tx_shift_reg <= {
                                    tx_shift_reg[6:0], 1'b0
                                };  // 시프트 진행
                                bit_cnt <= bit_cnt + 1;
                            end
                        end

                    end
                    READ_DATA: begin
                        if (scl_edge_rise) begin
                            rx_shift_reg <= {rx_shift_reg[6:0], sda_i};
                        end
                        if (scl_edge_falling) begin
                            bit_cnt <= bit_cnt + 1;
                            if (bit_cnt == 7) begin
                                rx_data <= rx_shift_reg;
                                state   <= DATA_ACK;
                                sda_r   <= 1'b1;
                                bit_cnt <= 0;
                            end
                        end
                    end
                    default: begin
                        state <= IDLE;
                    end
                endcase
            end
        end
    end

endmodule
