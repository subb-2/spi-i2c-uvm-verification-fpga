# SPI & I2C (설계 및 UVM 검증)

> SPI / I2C 통신 프로토콜 동작 원리 분석, RTL 설계, UVM 기반 검증 환경 구축 프로젝트  
> Basys3 (Xilinx Artix-7) 두 보드 간 실제 통신 동작 확인

---

## 📌 프로젝트 개요

SPI / I2C 통신 프로토콜을 직접 분석하고, SystemVerilog로 Master / Slave RTL을 설계한 뒤  
UVM 환경을 구축하여 기능 검증까지 수행한 프로젝트입니다.  
두 개의 Basys3 보드를 연결하여 실제 하드웨어 동작을 확인하였습니다.

---

## 🎯 프로젝트 목적

| 번호 | 목적 |
|------|------|
| 01 | SPI / I2C 통신 프로토콜 동작 원리 분석 |
| 02 | 통신 프로토콜 기반 RTL 설계 |
| 03 | UVM 기반 검증 환경 구축 및 기능 검증 |

---

## 📡 SPI

### SPI 통신 프로토콜

**신호선**

| 신호 | 방향 | 설명 |
|------|------|------|
| `SCLK` | Master → Slave | Master가 생성하는 동기 클럭 |
| `MOSI` | Master → Slave | Master 송신 / Slave 수신 데이터 |
| `MISO` | Slave → Master | Slave 송신 / Master 수신 데이터 |
| `CS_n` | Master → Slave | Slave 선택 신호 (Active Low) |

**SPI 특징**

- 4-wire 버스 (SCLK / MOSI / MISO / CS_N)
- 동기식 통신 — Master가 SCLK 생성
- Full-Duplex — MOSI / MISO 동시 송수신 가능
- 단일 Master, 다수 Slave — CS_n 개별 제어
- CPOL / CPHA — 4가지 동작 모드 지원

**CPOL / CPHA 모드**

| Mode | CPOL | CPHA | 데이터 샘플링 시점 |
|------|------|------|------------------|
| Mode 0 | 0 | 0 | Rising Edge |
| Mode 1 | 0 | 1 | Falling Edge |
| Mode 2 | 1 | 0 | Falling Edge |
| Mode 3 | 1 | 1 | Rising Edge |

> Protocol 스펙상 4가지 Mode가 존재하나, Mode 0만 지원하는 Slave가 가장 많이 사용됨

---

### SPI Master / Slave FSM

#### Master 상태 구성

```
IDLE → START → DATA → STOP
              ↑       ↓
              └───────┘ (bit_cnt < 7 반복)
```

- **IDLE**: `mosi=z`, `sclk=0`, `cs_n=1`, `phase=0` 유지, `start==1`이면 전환
- **START**: `tx_shift_reg` 로드, `cs_n=0` Assert, `bit_cnt=0`
- **DATA**: `half_tick==1`마다 `sclk` 토글, CPOL/CPHA에 따라 MOSI 출력 / MISO 샘플링
- **STOP**: `sclk_r=0`, `cs_n=1`, `done=1`, `busy=0`

> SCLK 10MHz 기준 `clk_div = 4` 설정

#### Slave 상태 구성

```
IDLE → START → DATA → STOP
               ↑      ↓
               └──────┘ (bit_cnt < 7 반복)
```

- **IDLE**: `cs_n==0` 감지 시 START로 전환
- **START**: `tx_shift_reg` 로드, `bit_cnt=0`
- **DATA**: `edge_rise` 시 MISO 출력, `edge_falling` 시 MOSI 수신

---

### SPI 시뮬레이션 검증

| 항목 | 값 |
|------|----|
| SCLK 주파수 | 10MHz (`clk_div = 4`) |
| Master tx_data | `0x55`, `0x12`, `0xFF`, `0xA5` |
| Slave tx_data | `0xAA`, `0x34`, `0xCC`, `0x5A` |
| 검증 내용 | MOSI / MISO 동시 송수신 정상 동작 확인 |

---

### SPI UVM 검증

#### UVM 환경 구성

```
  ┌─────────────────────────────────────────────────────────────────┐
  │  test                                                           │
  │  ┌──────────────────────────────────────────────┐              │
  │  │  env                                         │              │
  │  │  ┌───────────┐  ┌──────────────────────────┐ │ ┌──────────┐ │
  │  │  │   agent   │  │       Scoreboard         │ │ │ Coverage │ │
  │  │  │┌─────────┐│  │ exp: m_tx_data           │ │ │cp_tx_data│ │
  │  │  ││Sequencer││  │ act: MOSI 수집 값         │ │ │cp_clk_div│ │
  │  │  │├─────────┤│  │ exp: s_tx_data           │ │ │cp_mosi   │ │
  │  │  ││ Monitor ││  │ act: MISO 수집 값         │ │ │cp_miso   │ │
  │  │  │├─────────┤│  └──────────────────────────┘ │ └──────────┘ │
  │  │  ││ Driver  ││                               │              │
  │  │  │└─────────┘│                               │              │
  │  │  └───────────┘                               │              │
  │  └──────────────────────────────────────────────┘              │
  │  spi_if (interface)                                             │
  │  DUT : spi_master + spi_slave                                   │
  └─────────────────────────────────────────────────────────────────┘
```

#### Transaction 흐름

| 단계 | 컴포넌트 | 동작 |
|------|----------|------|
| 01 | Sequence | `clk_div`, `m_tx_data`, `s_tx_data` 랜덤 생성 |
| 02 | Driver | `start=1` 인가 → `m_done` 대기 → 신호 DUT로 Drive |
| 03 | DUT | `cs_n=0`, 8bit MOSI / MISO 전송 |
| 04 | Monitor | `cs_n` 하강 감지, SCLK Low→High마다 샘플링 |

#### Monitor 타이밍

```systemverilog
// 기존 (문제 있음) — sclk이 이미 HIGH면 즉시 통과
wait(sclk == 1);
@(mon_cb);

// 수정 후 — LOW를 먼저 확인하는 패턴
if (spi_if.mon_cb.sclk == 1'b1) begin
    wait(spi_if.mon_cb.sclk == 1'b0);  // LOW 확인
end
wait(spi_if.mon_cb.sclk == 1'b1);      // 상승엣지 대기
@(mon_cb);
```

#### Scoreboard 비교 기준

| 채널 | Expected | Actual |
|------|----------|--------|
| MOSI | `m_tx_data` | MOSI 수집 값 |
| MISO | `s_tx_data` | MISO 수집 값 |

#### Coverage 결과

| 항목 | 범위 | 결과 |
|------|------|------|
| `cp_clk_div` | 10MHz, 1MHz | 100.0% |
| `cp_mosi` | 0x00 ~ 0xFF | 100.0% |
| `cp_miso` | 0x00 ~ 0xFF | 100.0% |
| `cp_tx_data` | 0x00 ~ 0xFF | 100.0% |
| **Overall** | — | **100.0%** |
| Total Transactions | — | **2,560** |
| Total Errors | — | **0** |

> 8bit Data 기준 256가지 경우를 충분히 커버하기 위해 2,560회 진행

---

### SPI + FND 보드 연동

```
  sw[3:0] ──► tx_data ──► SPI Master ──SCLK──► SPI Slave ──► rx_done ──►┐
  BTN_down ──► start  ◄──────────────────MOSI────────────────────────    │
                          ◄──────────────MISO──────────────── tx_data ◄──┤
                                          CS                            FND
                                                                         │
                                                              mem[addr] <= idata (rx_done==1)
                                                              BTN counter → addr 선택
```

BTN 4개로 FND 4자리 각각의 주소를 선택, `rx_done==1`일 때만 해당 자리에 수신 데이터를 저장합니다.

---

## 🔄 I2C

### I2C 통신 프로토콜

**Transaction 흐름**

| 단계 | 설명 |
|------|------|
| START | SCL=1일 때 SDA fall |
| ADDR | 7bit 주소 + R/W bit 전송 |
| ACK | Slave가 SDA=0으로 응답 |
| DATA | 8bit 데이터 전송 |
| STOP | SCL=1일 때 SDA rise |

**I2C 특징**

- 2-wire 버스 (SCL / SDA, Open-Drain)
- 동기식 통신 — SCL 공유
- Half-Duplex — SDA 양방향 공유
- 주소 기반 통신 — 7bit / 10bit Slave 주소
- ACK / NACK — Byte마다 수신 확인

---

### I2C Master / Slave FSM

#### Master 상태 구성

```
IDLE → START → WAIT_CMD
                  ├── cmd_write ──► DATA ──► DATA_ACK ──► WAIT_CMD
                  ├── cmd_read  ──► DATA ──► DATA_ACK ──► WAIT_CMD
                  ├── cmd_stop  ──► STOP ──► IDLE
                  └── cmd_start ──► START
```

- **WAIT_CMD**: `cmd_write` / `cmd_read` / `cmd_stop` / `cmd_start` 감지
- **DATA**: `qtr_tick==1`마다 SCL / SDA 토글, `is_read` 플래그로 송수신 분기
- **DATA_ACK**: SCL 사이클 1회 동안 ACK/NACK 처리
- **STOP**: SDA를 SCL=1 구간에서 rise

#### Slave 상태 구성

```
IDLE ──(sda_fall & scl=1)──► ADDR ──(주소 일치)──► DATA_ACK
                                                      ├── from_addr==1 ──► WRITE_DATA
                                                      ├── bef_read      ──► READ_DATA
                                                      └── bef_write     ──► WRITE_DATA
```

- **ADDR**: `scl_rise`마다 SDA 수신하여 `rx_shift_reg`에 누적, 주소 일치 여부 확인
- **DATA_ACK**: `from_addr` 플래그로 Write/Read 분기 — ACK 전송 여부 결정
- **READ_DATA**: `scl_rise` 시 MOSI 수신, `scl_fall` 시 bit_cnt 증가
- **WRITE_DATA**: `scl_fall` 시 MSB부터 SDA 출력, `bit_cnt==8`이면 `sda_r=1`

---

### I2C UVM 검증

#### UVM 환경 구성

```
  ┌──────────────────────────────────────────────────────────────────┐
  │  test                                                            │
  │  ┌───────────────────────────────────────────────┐              │
  │  │  env                                          │              │
  │  │  ┌───────────┐  ┌───────────────────────────┐ │ ┌──────────┐ │
  │  │  │   agent   │  │       Scoreboard          │ │ │ Coverage │ │
  │  │  │┌─────────┐│  │ WRITE: exp=m_tx_data      │ │ │cp_m_tx   │ │
  │  │  ││Sequencer││  │        act=s_rx_data      │ │ │cp_s_tx   │ │
  │  │  │├─────────┤│  │ READ:  exp=m_tx_data      │ │ │cp_rw     │ │
  │  │  ││ Monitor ││  │        act=m_rx_data      │ │ │cx_m_tx_rw│ │
  │  │  │├─────────┤│  │ drv_imp → exp_queue push  │ │ │cx_s_rx_rw│ │
  │  │  ││ Driver  ││  │ mon_imp → exp_queue pop   │ │ └──────────┘ │
  │  │  │└─────────┘│  └───────────────────────────┘ │              │
  │  │  └───────────┘                                │              │
  │  └───────────────────────────────────────────────┘              │
  │  i2c_if (interface)                                              │
  │  DUT : i2c_master + i2c_slave                                    │
  └──────────────────────────────────────────────────────────────────┘
```

#### Transaction 흐름

| 단계 | 컴포넌트 | 동작 |
|------|----------|------|
| 01 | Sequence | Command 신호 순서 생성, `s_tx_data` / `m_tx_data` 랜덤 생성 |
| 02 | Driver | DUT에 신호 인가, `m_done` 대기 → `rx_data` 읽기 |
| 03 | Monitor | `m_done` 타이밍에 샘플링, `ap.write` |
| 04 | Scoreboard | `drv_imp` → `exp_queue` push / `mon_imp` → `exp_queue` pop 후 비교 |

#### Monitor 타이밍

- `@(mon_cb)` — `cmd_write` / `cmd_read` 감지 시 `m_tx`, `s_tx` 캡처
- `m_done==1` 시점에 `m_rx`, `s_rx` 샘플링
- 주소 (`0x24` / `0x25`) 제외한 데이터만 `ap.write`
- `is_write` / `is_read` 플래그 초기화 (중복 방지)

#### Scoreboard 비교 기준

| 방향 | Expected | Actual |
|------|----------|--------|
| WRITE | `exp_item.m_tx_data` | `item.s_rx_data` |
| READ | `exp_item.m_tx_data` | `item.m_rx_data` |

#### Coverage 결과

| 항목 | 범위 | 결과 |
|------|------|------|
| `cp_m_tx_data` | 0x00 ~ 0xFF | 100.0% |
| `cp_s_tx_data` | 0x00 ~ 0xFF | 100.0% |
| `cp_rw` | Write / Read | 100.0% |
| `cx_m_tx_rw` | m_tx × rw 교차 | 100.0% |
| `cx_s_rx_rw` | s_rx × rw 교차 | 100.0% |
| `cx_m_rx_rw` | m_rx × rw 교차 | 100.0% |
| `cx_s_tx_rw` | s_tx × rw 교차 | 100.0% |
| **Overall** | — | **100.0%** |
| Total Transactions | — | **2,560** |

> 8bit Data 기준 256가지 경우를 충분히 커버하기 위해 2,560회 진행

---

### I2C + FND 보드 연동

```
  sw[7:0] ──► tx_data ──► I2C Master ──SCL──► I2C Slave ──► rx_data ──► FND
  sw[15]  ──► start        ◄──────────SDA──────────────────────────────
                            (주소 고정, 0 ~ 255 표시 가능)
```

`sw[15]`를 start 신호로 사용하여 I2C 전송을 트리거하고,  
Slave에서 수신한 `rx_data`를 FND에 출력합니다 (0 ~ 255 표시 가능).

---

## 🖥️ 개발 환경

| 항목 | 내용 |
|------|------|
| HDL | SystemVerilog |
| EDA Tool | Xilinx Vivado |
| 타겟 보드 | Basys3 (Xilinx Artix-7) |
| 시뮬레이터 | Vivado Simulator (XSim) |
| 검증 방법론 | UVM (Universal Verification Methodology) |

---

## 📁 파일 구성

```
├── spi_master.sv          # SPI Master RTL (CPOL/CPHA 지원, clk_div 설정)
├── spi_slave.sv           # SPI Slave RTL (edge_rise/edge_falling 기반)
├── i2c_master.sv          # I2C Master RTL (START/DATA/DATA_ACK/STOP FSM)
├── i2c_slave.sv           # I2C Slave RTL (ADDR/DATA_ACK/READ_DATA/WRITE_DATA FSM)
├── uvm/
│   ├── spi_seq_item.sv    # SPI Transaction Item (clk_div, m_tx_data, s_tx_data)
│   ├── spi_sequence.sv    # SPI Sequence (랜덤 생성 2560회)
│   ├── spi_driver.sv      # SPI Driver (AXI Write/Read 수행)
│   ├── spi_monitor.sv     # SPI Monitor (cs_n 하강 감지, sclk 엣지 샘플링)
│   ├── spi_scoreboard.sv  # SPI Scoreboard (MOSI/MISO 비교)
│   ├── spi_coverage.sv    # SPI Coverage (cp_tx_data, cp_clk_div, cp_mosi, cp_miso)
│   ├── i2c_seq_item.sv    # I2C Transaction Item
│   ├── i2c_sequence.sv    # I2C Sequence
│   ├── i2c_driver.sv      # I2C Driver
│   ├── i2c_monitor.sv     # I2C Monitor (m_done 타이밍 샘플링)
│   ├── i2c_scoreboard.sv  # I2C Scoreboard (WRITE/READ 방향별 비교)
│   └── i2c_coverage.sv    # I2C Coverage (cp_rw, cx_m_tx_rw, cx_s_rx_rw 등)
└── top/
    ├── btn_sw_spi_fnd_top.sv  # BTN + SW + SPI + FND 통합 Top
    └── sw_i2c_fnd_top.sv      # SW + I2C + FND 통합 Top
```

---

## 🐛 Trouble Shooting

### 1. SPI UVM Monitor — `wait` 레벨 감지 오류

**문제**: SCLK이 이미 HIGH인 구간에서 `wait(sclk==1)`을 만나면 대기 없이 즉시 통과되어, 동일 비트를 중복 샘플링하는 오류 발생.

**원인**: SystemVerilog의 `wait`은 현재 값이 조건을 만족하면 즉시 통과하는 레벨 감지 방식.  
HIGH 구간 중에 루프가 다시 돌아오면 `wait(sclk==1)`이 그냥 통과되어 오류 누적.

**해결**: LOW를 먼저 확인하는 패턴으로 변경하여 반드시 상승엣지를 기다리도록 수정.

```systemverilog
// 수정 전 — 레벨 감지로 인한 즉시 통과 위험
for (int i = 0; i < 8; i++) begin
    wait(spi_if.mon_cb.sclk == 1'b1);
    @(spi_if.mon_cb);
    shift_mosi = {shift_mosi[6:0], spi_if.mon_cb.mosi};
    if (i < 7) begin
        wait(spi_if.mon_cb.sclk == 1'b1);
        @(spi_if.mon_cb);
    end
end

// 수정 후 — LOW 확인 후 상승엣지 대기
for (int i = 0; i < 8; i++) begin
    // sclk이 HIGH면 먼저 LOW로 내려갈 때까지 대기
    if (spi_if.mon_cb.sclk == 1'b1) begin
        wait(spi_if.mon_cb.sclk == 1'b0);  // LOW 확인
    end
    // LOW 확인 후 상승엣지 대기
    wait(spi_if.mon_cb.sclk == 1'b1);
    @(spi_if.mon_cb);
    shift_mosi = {shift_mosi[6:0], spi_if.mon_cb.mosi};
end
```

### 2. SPI FND — BTN 주소 지정 시 데이터 덮어쓰기

**문제**: BTN count로 FND 자릿수별 주소를 지정하려 했으나, 매 클럭마다 새 값이 계속 쓰여 원하는 자리에만 저장이 안 됨.

**원인**: 수신 완료 여부와 관계없이 항상 `mem[addr] <= idata`가 실행됨.

**해결**: `rx_done` 신호를 쓰기 인에이블로 추가하여, SPI 수신 완료 시점에만 메모리에 저장.

```systemverilog
// 수정 후 — rx_done==1일 때만 저장
always @(posedge clk) begin
    if (rx_done)
        mem[addr] <= idata;
end
```

### 3. I2C Slave — Read 명령 수신 시 ACK 미전송 문제

**문제**: Addr 데이터를 받고 R/W 비트가 Read(`1`)이면, Slave가 ACK를 전송하지 않고 대기 상태에 빠짐.

**원인**: `DATA_ACK` 상태에서 Write / Read 방향 구분 없이 동일하게 ACK를 처리했으나,  
Read일 때는 Slave가 즉시 데이터를 출력해야 하는 타이밍 분기가 누락됨.

**해결**: `from_addr` 플래그를 추가하여, 주소 수신 직후인지 데이터 수신 이후인지를 구분.  
`from_addr==1`이면 Slave가 첫 번째 데이터 바이트를 MSB부터 출력하도록 분기 처리.

```
DATA_ACK 상태
    ├── from_addr == 1 → sda_r = tx_data[7] → WRITE_DATA
    ├── bef_read       → READ_DATA
    └── bef_write      → WRITE_DATA
```
