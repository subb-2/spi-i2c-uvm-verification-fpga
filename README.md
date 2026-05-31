# SystemVerilog Design & Verification — SPI & I2C 설계 및 UVM 검증

📅 프로젝트 정보

* 진행 기간: 2026.04.13 ~ 2026.04.19
* 설계 및 검증 대상: `SPI Master / Slave RTL`, `I2C Master / Slave RTL`, `UVM 검증 환경`
* 기술 스택: `SystemVerilog`, `Vivado XSim`, `UVM (Universal Verification Methodology)`

---

## 📝 프로젝트 개요

SPI / I2C 통신 프로토콜을 직접 분석하고, SystemVerilog로 Master / Slave RTL을 설계한 뒤 UVM 환경을 구축하여 기능 검증까지 수행한 프로젝트입니다.  
단순 통신 동작 구현을 넘어, **SPI Master CPOL / CPHA 4가지 모드 구현**, **I2C Slave FSM에서 Write / Read 방향 분기 처리**, **UVM Verification** 등 프로토콜 스펙을 직접 해석하고 검증하는 데 집중하였습니다.  
최종적으로 두 개의 Basys3 보드를 연결하여 SPI / I2C 실제 통신 동작을 확인하였습니다.

---

## 🔑 주요 구현 내용

### 1. SPI Master / Slave RTL 설계

* **Protocol**: 4-wire 동기식 Full-Duplex 통신. SCLK / MOSI / MISO / CS_n 4개 신호선. Master가 SCLK을 생성하고 Shift Register를 통해 동시에 송수신.
* **CPOL / CPHA**: 4가지 동작 모드(Mode 0~3) 지원. 실제 Slave 구현에서 가장 많이 사용되는 Mode 0(CPOL=0, CPHA=0)을 기준으로 검증.

* **Master FSM**: `IDLE → START → DATA → STOP`. `half_tick==1`마다 SCLK 토글, CPOL/CPHA에 따라 MOSI 송신 / MISO 샘플링. SCLK 10MHz 기준 `clk_div = 4` 설정.
* **Slave FSM**: `IDLE → START → DATA → STOP`. `cs_n==0` 감지 시 START 진입, `edge_rise` 시 MOSI 수신, `edge_falling` 시 MISO 송신.

### 2. I2C Master / Slave RTL 설계

* **Protocol**: 2-wire Half-Duplex 주소 기반 통신. SCL / SDA (Open-Drain). 7bit Slave 주소 + R/W bit로 대상 지정, Byte마다 ACK/NACK 수신 확인.
* **Master FSM**: `IDLE → START → WAIT_CMD` 구조. `WAIT_CMD`에서 `cmd_write` / `cmd_read` / `cmd_stop` / `cmd_start`를 감지하여 분기. `DATA` 상태에서 `qtr_tick==1`마다 SCL / SDA 토글, `is_read` 플래그로 송수신 분기.

```
IDLE → START → WAIT_CMD
                  ├── cmd_write ──► DATA ──► DATA_ACK ──► WAIT_CMD
                  ├── cmd_read  ──► DATA ──► DATA_ACK ──► WAIT_CMD
                  ├── cmd_stop  ──► STOP ──► IDLE
                  └── cmd_start ──► START
```

* **Slave FSM**: `IDLE → ADDR → DATA_ACK → WRITE_DATA / READ_DATA`. `from_addr` 플래그를 통해 주소 수신 직후 Write/Read 방향을 분기하여 ACK 전송 및 데이터 출력 타이밍을 결정.

```
IDLE ──(sda_fall & scl=1)──► ADDR ──(주소 일치)──► DATA_ACK
                                                      ├── from_addr == 1 ──► WRITE_DATA
                                                      ├── bef_read      ──► READ_DATA
                                                      └── bef_write     ──► WRITE_DATA
```

### 3. SPI UVM 검증 환경

* **Architecture**: test → env(agent + scoreboard + coverage) 계층 구조. Monitor가 `cs_n` 하강을 감지하고 SCLK Low→High 전환마다 MOSI / MISO를 샘플링하여 Scoreboard에 전달.
* **Scoreboard**: MOSI 채널은 `m_tx_data` vs 수집된 MOSI 값, MISO 채널은 `s_tx_data` vs 수집된 MISO 값을 비교.
* **Coverage**: `cp_tx_data` (0x00~0xFF 전 범위), `cp_clk_div` (10MHz / 1MHz), `cp_mosi` / `cp_miso` (0x00~0xFF 전 범위).

### 4. I2C UVM 검증 환경

* **Architecture**: test → env(agent + scoreboard + coverage) 계층 구조. Scoreboard는 `drv_imp` / `mon_imp` 이중 포트 구조로, Driver에서 `exp_queue`에 push하고 Monitor에서 pop하여 비교.
* **Monitor 타이밍**: `@(mon_cb)` 기준으로 `cmd_write` / `cmd_read` 감지 시 `m_tx` / `s_tx` 캡처. `m_done==1` 시점에 `m_rx` / `s_rx` 샘플링. 주소(`0x24` / `0x25`) 제외한 데이터만 `ap.write`.
* **Scoreboard**: Write 방향은 `exp_item.m_tx_data` vs `item.s_rx_data`, Read 방향은 `exp_item.m_tx_data` vs `item.m_rx_data` 비교.
* **Coverage**: `cp_m_tx_data` / `cp_s_tx_data` (0x00~0xFF), `cp_rw` (Write/Read), `cx_m_tx_rw` / `cx_s_rx_rw` / `cx_m_rx_rw` / `cx_s_tx_rw` (교차 커버리지).

---

## 🏗️ 시스템 구조

### SPI Master / Slave Block Diagram

```
  ┌──────────────────┐   SCLK   ┌──────────────────┐
  │   SPI Master     │─────────►│   SPI Slave      │
  │                  │   MOSI   │                  │
  │  clk_div ──► FSM │─────────►│ FSM ──► rx_data  │
  │  tx_data         │   MISO   │     ◄── tx_data  │
  │  start           │◄─────────│                  │
  │  ◄── done/busy   │    CS    │ ◄── cs_n         │
  └──────────────────┘─────────►└──────────────────┘
```

### I2C Master / Slave Block Diagram

```
  ┌──────────────────┐          ┌──────────────────┐
  │   I2C Master     │   SCL    │   I2C Slave      │
  │                  │─────────►│                  │
  │  cmd_start       │   SDA    │  rx_data ──► FND │
  │  cmd_write  ◄───►│◄────────►│  tx_data         │
  │  cmd_read        │          │  SLAVE_ADDR=0x12 │
  │  cmd_stop        │          │                  │
  │  ◄── done/busy   │          │                  │
  └──────────────────┘          └──────────────────┘
```

<table>
<tr>

<td width="49%">

### UVM 환경 구성 (SPI)

<img width="531" height="501" alt="Image" src="https://github.com/user-attachments/assets/e14628f0-2d75-4a7a-bd4d-8a2ad5185688" />


</td>

<td width="2%">
</td>

<td width="49%">

### UVM 환경 구성 (I2C)

<img width="532" height="501" alt="Image" src="https://github.com/user-attachments/assets/fe3d9495-159e-4bbe-b4f4-04ce99c1c0d1" />

</td>

</tr>
</table>

---

## ✅ 검증 결과

<table>
<tr>
<td width="50%">

**SPI UVM 검증**

| 항목 | 결과 |
|------|------|
| Total Transactions | 2,560 |
| Overall Coverage | **100.0%** |
| `cp_clk_div` | 100.0% (10MHz / 1MHz) |
| `cp_mosi` | 100.0% (0x00~0xFF) |
| `cp_miso` | 100.0% (0x00~0xFF) |
| `cp_tx_data` | 100.0% (0x00~0xFF) |
| Scoreboard PASS | **2,560** |
| Scoreboard FAIL | **0** |

</td>

<td width="6%">
</td>

<td width="50%">

**I2C UVM 검증**

| 항목 | 결과 |
|------|------|
| Total Transactions | 2,560 |
| Overall Coverage | **100.0%** |
| `cp_m_tx_data` | 100.0% (0x00~0xFF) |
| `cp_s_tx_data` | 100.0% (0x00~0xFF) |
| `cp_rw` | 100.0% (Write / Read) |
| `cx_m_tx_rw` / `cx_s_rx_rw` | 100.0% (교차 커버리지) |
| `cx_m_rx_rw` / `cx_s_tx_rw` | 100.0% (교차 커버리지) |
| Scoreboard PASS | **2,560** |
| Scoreboard FAIL | **0** |

</td>
</tr>
</table>

> 8bit 데이터 기준 256가지 경우를 충분히 커버하기 위해 2,560회 트랜잭션 진행

**실보드 통신 검증 (Basys3 2보드)**

| 프로토콜 | 검증 내용 | 결과 |
|----------|-----------|------|
| SPI | Master `sw[3:0]` → Slave FND 수신 표시 (BTN 주소 지정) | ✅ PASS |
| I2C | Master `sw[7:0]` → Slave FND 수신 표시 (`sw[15]` start) | ✅ PASS |

---

## 🚀 문제 해결 (Troubleshooting)

### 1. SPI UVM Monitor — `wait` 레벨 감지 오류

* **문제**: SCLK이 이미 HIGH인 구간에서 `wait(sclk==1)`을 만나면 대기 없이 즉시 통과되어, 동일 비트를 중복 샘플링하는 오류 발생.
* **원인**: SystemVerilog의 `wait`은 현재 값이 조건을 만족하면 즉시 통과하는 레벨 감지 방식. HIGH 구간 중에 루프가 다시 돌아오면 `wait(sclk==1)`이 그냥 통과되어 오류 누적.
* **해결**: LOW를 먼저 확인하는 패턴으로 변경하여 반드시 상승엣지를 기다리도록 수정.

### 2. SPI FND — BTN 주소 지정 시 데이터 덮어쓰기

* **문제**: BTN count로 FND 자릿수별 주소를 지정하려 했으나, 매 클럭마다 새 값이 계속 쓰여 원하는 자리에만 저장이 안 됨.
* **원인**: 수신 완료 여부와 관계없이 항상 `mem[addr] <= idata`가 실행됨.
* **해결**: `rx_done` 신호를 쓰기 인에이블로 추가하여, SPI 수신 완료 시점에만 메모리에 저장.

### 3. I2C Slave — Read 명령 수신 시 ACK 미전송 문제

* **문제**: ADDR 데이터를 받고 R/W 비트가 Read(`1`)이면, Slave가 ACK를 전송하지 않고 대기 상태에 빠짐.
* **원인**: `DATA_ACK` 상태에서 Write / Read 방향 구분 없이 동일하게 ACK를 처리했으나, Read일 때 Slave가 즉시 데이터를 출력해야 하는 타이밍 분기가 누락됨.
* **해결**: `from_addr` 플래그를 추가하여 주소 수신 직후인지 데이터 수신 이후인지를 구분. `from_addr==1`이면 Slave가 첫 번째 데이터 바이트를 MSB부터 출력하도록 분기 처리.


---

## 📚 배운 점

* **레벨 감지 vs 엣지 감지**: `wait(signal==value)`가 현재 레벨이 조건을 만족하면 즉시 통과한다는 점을 간과하면 UVM Monitor에서 비트 중복 샘플링 오류가 발생함. 시뮬레이션 레벨에서 동작 방식을 정확히 이해하고, LOW 확인 후 상승엣지를 기다리는 패턴으로 명시적으로 작성해야 함을 체감.
* **FSM 설계에서 플래그 추가의 중요성**: I2C Slave의 `from_addr` 플래그처럼, 상태 자체만으로 분기가 불충분할 때 보조 플래그를 도입하는 것이 상태 수를 늘리지 않고 타이밍 분기를 정확히 처리하는 효과적인 방법임을 이해. 플래그 추가 여부는 FSM 설계 초기에 시퀀스 다이어그램을 통해 검토하는 것이 중요.
* **UVM 검증 환경 설계**: 단순히 환경을 구축하는 것을 넘어, Scoreboard의 비교 대상(Expected / Actual)이 정확한 소스를 참조하는지, Monitor의 샘플링 시점이 프로토콜 타이밍과 일치하는지를 먼저 설계 단계에서 정의해야 검증 신뢰성이 확보됨을 직접 경험.

---

## 🖥️ 개발 환경

| 항목 | 내용 |
|------|------|
| HDL | SystemVerilog (IEEE 1800) |
| EDA Tool | Xilinx Vivado |
| 타겟 보드 | Basys3 (Xilinx Artix-7) × 2 |
| 시뮬레이터 | Vivado Simulator (XSim) |
| 검증 방법론 | UVM (Universal Verification Methodology) |
| 타겟 클럭 | 100MHz (SCLK 10MHz / 1MHz 설정) |

---

## 📁 파일 구성

```text
SPI
├── spi_master.sv              # SPI Master RTL (CPOL/CPHA 지원, clk_div 설정)
├── spi_slave.sv               # SPI Slave RTL (edge_rise/edge_falling 기반)
├── btn_sw_spi_fnd_top.sv      # BTN + SW + SPI + FND 통합 Top (주소 지정)
└── tb_spi_uvm.sv              # SPI UVM Testbench (test/env/agent/scoreboard/coverage)

I2C
├── i2c_master.sv              # I2C Master RTL (START/DATA/DATA_ACK/STOP FSM)
├── i2c_slave.sv               # I2C Slave RTL (ADDR/DATA_ACK/READ_DATA/WRITE_DATA FSM)
├── sw_i2c_fnd_top.sv          # SW + I2C + FND 통합 Top (sw[15]=start, sw[7:0]=data)
└── tb_i2c_uvm.sv              # I2C UVM Testbench (test/env/agent/scoreboard/coverage)

UVM (공통)
├── spi_seq_item.sv            # SPI Transaction Item (clk_div, m_tx_data, s_tx_data)
├── spi_sequence.sv            # SPI Sequence (랜덤 생성, 2,560회)
├── spi_driver.sv              # SPI Driver (start 인가 → m_done 대기)
├── spi_monitor.sv             # SPI Monitor (cs_n 하강 감지, sclk 엣지 샘플링)
├── spi_scoreboard.sv          # SPI Scoreboard (MOSI/MISO 비교)
├── spi_coverage.sv            # SPI Coverage (cp_tx_data, cp_clk_div, cp_mosi, cp_miso)
├── i2c_seq_item.sv            # I2C Transaction Item (cmd 순서, m_tx_data, s_tx_data)
├── i2c_sequence.sv            # I2C Sequence (랜덤 생성, 2,560회)
├── i2c_driver.sv              # I2C Driver (cmd 인가 → m_done 대기 → rx_data 읽기)
├── i2c_monitor.sv             # I2C Monitor (m_done 타이밍 샘플링, 주소 제외)
├── i2c_scoreboard.sv          # I2C Scoreboard (WRITE/READ 방향별 비교)
└── i2c_coverage.sv            # I2C Coverage (cp_rw, cx_m_tx_rw, cx_s_rx_rw 등)
```
