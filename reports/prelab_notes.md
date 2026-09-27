# LAB3-20 · RGB LED PWM 실험 전 보고서

- 작성자: 상혁 (서울시립대학교 전자전기컴퓨터공학부, 학번 2025440084)
- top 모듈: `lab3_rgb_pwm`
- 프로젝트: `lab3_20_rgb_pwm` (fpga-lab-template v2.0.2, `main` 브랜치)
- FPGA Part: xc7s75fgga484-1 (Combo II-DLD S75)

## 1. 회로 목적

R·G·B 세 개의 버튼으로 R/G/B 세 채널의 PWM duty를 각각 독립적으로 0~LEVELS 단계로
증가시키고(LEVELS에서 다시 0으로 순환), 그 결과를 4비트씩 묶인 RGB LED 12개 핀에 출력하여
버튼 조작만으로 색 혼합과 밝기를 바꿀 수 있게 하는 회로다. 최상위 클록은 50MHz
`clk_50mhz` 하나뿐이며, 모든 순차 로직은 이 클록만 사용한다.

## 2. 블록 흐름

```
button_r/g/b (비동기, 기계식 버튼)
      │
      ▼
button_onepulse ×3  ── 2단 동기화 + 디바운스 → 눌림당 1클록 원펄스(press_r/g/b)
      │
      ▼
level_r/g/b 레지스터 ── press_* 펄스마다 +1, LEVELS에서 0으로 순환 (0..LEVELS, LEVELS+1단계)
      │
      ▼
pwm_channel ×3      ── level → threshold = PERIOD_CYCLES*level/LEVELS 환산,
      │                자유 실행 카운터(count)로 count<threshold 구간만 HIGH
      ▼
pwm_r/g/b → {4{pwm}} 로 4비트 복제 → led_r[3:0], led_g[3:0], led_b[3:0]
```

버튼 3개 → `button_onepulse` 3개(동일 모듈 재사용) → 공유 레벨 레지스터 → `pwm_channel` 3개
(채널마다 독립 카운터/threshold) → LED 출력이라는 완전히 독립적인 3채널 구조다. 세 채널은
같은 클록·같은 PERIOD_CYCLES(공통 PWM 주기)만 공유하고 duty(threshold)는 서로 무관하게
동작한다.

## 3. 파라미터 계산

| 파라미터 | 보드(실동작) 값 | 계산 | 시뮬레이션(축소) 값 |
|---|---|---|---|
| CLK_HZ | 50,000,000 | 보드 MAIN CLOCK F | 1,000 |
| PWM_HZ | 1,000 | 목표 PWM 주파수(가청/가시 깜빡임 방지 위해 1kHz) | 100 |
| PERIOD_CYCLES | 50,000 | CLK_HZ / PWM_HZ = 50,000,000 / 1,000 | 10 (= 1,000 / 100) |
| PWM 주기(시간) | 1 ms | 50,000 × 20 ns | 100 µs (10 × 10 ns... 실제론 200ns, 아래 설명) |
| LEVELS | 10 | 0~LEVELS의 11단계(0%,10%,...,100%) | 10 (동일) |
| threshold(level) | PERIOD_CYCLES·level/LEVELS | level=2,5,8 → 20%,50%,80% duty | 동일 비율 |
| DEBOUNCE_CYCLES | 1,000,000 | 20 ms 안정 시간(50MHz×20ms) | 2 (시뮬레이션 시간 단축용) |
| COUNT_WIDTH(PWM 카운터) | 16 bit | $clog2(50,000)=16 (2¹⁶=65,536 ≥ 50,000) | 4 bit ($clog2(10)=4) |
| COUNT_WIDTH(디바운스 카운터) | 20 bit | $clog2(1,000,000)=20 | 1 bit ($clog2(2)=1) |
| clk 주기 | 20 ns | 1 / 50 MHz | TB에서도 20 ns(`#10` 토글) 유지 |

주: 시뮬레이션 PWM 주기(시간)는 클록 반주기 10ns × PERIOD_CYCLES(10) = 100ns가 아니라,
클록 자체가 20ns 주기이므로 10사이클 × 20ns = 200ns다. duty 비율(level/LEVELS)은
CLK_HZ·PWM_HZ 값과 무관하게 항상 동일하게 유지되도록 설계했다(threshold 공식이 비율 기반).

## 4. 상태/타이밍 표

| 신호 | 의미 | 폭/타이밍 |
|---|---|---|
| `button_meta`, `button_sync` | 2단 동기화 플립플롭 | posedge clk마다 1단씩 전파, ASYNC_REG 속성 부여 |
| `stable_count` | 디바운스 카운터 | button_sync가 accepted와 다른 상태로 STABLE_CYCLES(보드: 1,000,000 = 20ms)유지되면 accepted 갱신 |
| `pulse` | 원펄스 출력 | accepted 갱신 순간(눌림 방향, button_sync=1)에만 1클록 폭 HIGH |
| `level_r/g/b` | 3비트+1(0..LEVELS) 레벨 레지스터 | press_* 펄스 posedge에서 +1, LEVELS 도달 시 다음 펄스에 0으로 순환 |
| `count` (pwm_channel) | 자유 실행 카운터 | 0..PERIOD_CYCLES-1 반복(보드: 0..49,999) |
| `threshold` | 콤비 로직(always @*) | level≥LEVELS면 PERIOD_CYCLES(100%), 아니면 PERIOD_CYCLES×level/LEVELS |
| `pwm` | 등록 출력 | count<threshold 구간 동안 다음 클록에서 HIGH(1클록 지연 등록) |
| 리셋 우선순위 | `rst_p`(active-high, 비동기) | 모든 always 블록에서 `if (rst_p)`를 최우선으로 처리, 카운터/레벨/pulse 모두 0으로 |

## 5. RTL·TB·XDC 역할 설명

- **`src/lab3_rgb_pwm.v (button_onepulse.v, pwm_channel.v 포함)`**: 합성 가능한 RTL. `button_onepulse`(비동기 버튼 → 동기화+디바운스 원펄스),
  `pwm_channel`(레벨 → duty 비율 PWM 생성), 최상위 `lab3_rgb_pwm`(위 두 모듈을 R/G/B 3벌
  인스턴스화하고 레벨 레지스터·LED 출력을 연결) 세 모듈을 한 파일에 순서대로 정의한다.
  최상위 합성 top은 `lab3_rgb_pwm`이며 TB 모듈을 합성 top으로 선택하지 않는다.
- **`sim/tb_rgb_pwm.sv`**: 입력 자극(press_r/g/b 태스크로 버튼을 6클록 HIGH+6클록 LOW 유지)과
  기대값 비교(measure 태스크에서 PWM 한 주기(10클록) 동안 LED HIGH 샘플 수를 세어 기대
  duty와 `!==` 비교, 불일치 시 `$fatal`)를 담당한다. 통과마다 `PASS: check N ...`을 출력하고
  마지막에 `LAB3_RGB_PWM_PASS checks=2` 및 `TOTAL: 2 checks passed`를 요약 출력한다.
  `$dumpfile("wave.vcd")`/`$dumpvars`로 파형을 남기고, 30,000 단위 시간 타임아웃으로 `$fatal`
  하여 결정적으로 종료(`$finish`)한다.
- **`constraints/lab3_rgb_pwm.xdc`**: 논리 시뮬레이션에는 쓰이지 않으며, 보드 핀(PACKAGE_PIN)과
  IOSTANDARD LVCMOS33, 20.000ns 클록 제약(`create_clock`), 비동기 입력(rst_p/button_r/g/b)에
  대한 `set_false_path`를 담당한다. `get_ports` 대상은 `lab3_rgb_pwm`의 포트명(`clk_50mhz`,
  `rst_p`, `button_r/g/b`, `led_r/g/b[3:0]`)과 정확히 일치시켰다.

## 6. TB 자극 → 기대 결과 표

| 순서 | 자극 | 기대 level(R,G,B) | 기대 duty(10클록 중 HIGH 수) | 결과 |
|---|---|---|---|---|
| 1 | reset 3클록 후 해제 | (0,0,0) | - | - |
| 2 | press_r() ×2 | level_r=2 | R HIGH 2/10 | check 1 |
| 3 | press_g() ×5 | level_g=5 | G HIGH 5/10 | check 1 |
| 4 | press_b() ×8 | level_b=8 | B HIGH 8/10 | check 1 |
| 5 | `measure(2,5,8,1)` | (2,5,8) | R=20%, G=50%, B=80% | **PASS: check 1** |
| 6 | press_r() ×1(추가) | level_r=3 (G,B 불변) | R HIGH 3/10, G/B 그대로 | check 2 |
| 7 | `measure(3,5,8,2)` | (3,5,8) | R=30%, G=50%, B=80% | **PASS: check 2** |

check 2는 "R 채널만 한 단계 증가"하고 G/B는 이전 값을 그대로 유지하는지 검증하는
독립 채널 확인 조건이다.

## 7. Icarus PASS 결과 핵심 로그

`python3 tools/fpga_lab.py simulate` 실행 결과 (`build/sim/result.json` status = `SIMULATED`):

```
VCD info: dumpfile wave.vcd opened for output.
PASS: check 1 duty R=2/10 G=5/10 B=8/10 (level_r=2 level_g=5 level_b=8)
PASS: check 2 duty R=3/10 G=5/10 B=8/10 (level_r=3 level_g=5 level_b=8)
LAB3_RGB_PWM_PASS checks=2
TOTAL: 2 checks passed
sim/tb_rgb_pwm.sv:74: $finish called at 4431000 (1ps)
```

컴파일(iverilog -g2012 -Wall) 경고/에러 없음, `vvp` 종료 코드 0, `wave.vcd` 생성 및
`$var`/시간 진행 확인됨.

## 8. 한 항목 수정 실험과 복구 결과

`pwm_channel`의 threshold 계산식 한 줄을 의도적으로 변경하여 오류를 주입했다.

- 수정 위치: `src/lab3_rgb_pwm.v (button_onepulse.v, pwm_channel.v 포함)`, `threshold = (PERIOD_CYCLES * level) / LEVELS;`
  → `threshold = (PERIOD_CYCLES * level) / (LEVELS + 1);` (분모에 +1, 명백한 계산 오류)
- TB의 기대값은 그대로 두었다(RTL 오류에 맞춰 TB를 바꾸지 않음).

| 항목 | 예상값 | 실제 결과(수정 후) | 복구 후 |
|---|---|---|---|
| check 1 duty (R,G,B) | 2,5,8 | **FAIL** → 실제 1,4,7 (threshold가 11로 나뉘어 작아짐) | PASS 복구: 2,5,8 |
| 시뮬레이션 상태 | SIMULATED | **FAILED** (`vvp` 종료 코드 1) | SIMULATED 복구 |
| 로그 메시지 | - | `FATAL: ... FAIL: check 1 expected R=2 G=5 B=8 got R=1 G=4 B=7` (Time: 3851000, Scope: tb_design.measure) | `PASS: check 1 ...` / `PASS: check 2 ...` / `LAB3_RGB_PWM_PASS checks=2` 정상 출력 |

`(LEVELS+1)`로 나누면 threshold(level=2)=10×2/11=1(정수 나눗셈), threshold(level=5)=4,
threshold(level=8)=7이 되어 기대값(2,5,8)과 불일치 → TB가 정확히 `$fatal`로 검출했다.
이후 원래 식으로 되돌리고 재실행하여 두 check 모두 PASS, `LAB3_RGB_PWM_PASS checks=2`가
다시 출력됨을 확인했다.

## 9. 실제 보드 확인 체크리스트

- [ ] 전원을 끈 상태에서 외부 부품 결선과 공통 GND를 먼저 확인한다.
- [ ] Vivado에서 Open Elaborated Design/I/O Planning으로 top port와 PACKAGE_PIN 대조.
- [ ] Reports → Timing → Report Clocks에서 `clk_50mhz` 주기 20.000ns 확인.
- [ ] Run Synthesis → Run Implementation → Generate Bitstream, DRC/타이밍 위반 없음 확인.
- [ ] Hardware Manager → Open Target → Auto Connect → Program Device.
- [ ] R/G/B 버튼 각각이 해당 색 LED duty만 바꾸는지 확인(다른 채널 영향 없음).
- [ ] 버튼을 반복 눌러 LEVELS에서 0으로 순환(wrap)하는지 확인.
- [ ] 세 색의 조합(예: R+G+B 동시 밝기) 및 밝기 변화(육안상 duty 증가에 따른 밝기 증가)를
      사진·영상으로 기록.
- [ ] 예상 결과: 버튼을 누를 때마다 해당 LED duty가 1/LEVELS(10%)씩 증가, LEVELS+1(11)단계에서
      순환, 다른 두 채널은 값 유지.
- [ ] Icarus(SIMULATED, PASS)와 Vivado XSim(Tcl Console `LAB3_RGB_PWM_PASS checks=2`)이 같은
      RTL·TB로 동일 결과를 내는지 재확인.

## 10. 핀 표 요약 (신호명 / PACKAGE_PIN / IOSTANDARD)

| 신호명 | PACKAGE_PIN | IOSTANDARD |
|---|---|---|
| clk_50mhz | B6 | LVCMOS33 |
| rst_p | K4 | LVCMOS33 |
| button_r | N8 | LVCMOS33 |
| button_g | N4 | LVCMOS33 |
| button_b | N1 | LVCMOS33 |
| led_r[3] | T2 | LVCMOS33 |
| led_r[2] | U1 | LVCMOS33 |
| led_r[1] | P2 | LVCMOS33 |
| led_r[0] | R3 | LVCMOS33 |
| led_g[3] | U5 | LVCMOS33 |
| led_g[2] | V1 | LVCMOS33 |
| led_g[1] | R7 | LVCMOS33 |
| led_g[0] | T6 | LVCMOS33 |
| led_b[3] | U3 | LVCMOS33 |
| led_b[2] | W2 | LVCMOS33 |
| led_b[1] | R5 | LVCMOS33 |
| led_b[0] | T3 | LVCMOS33 |

추가 제약: `create_clock -name clk_50mhz -period 20.000 [get_ports clk_50mhz]`,
`set_false_path -from [get_ports {rst_p button_r button_g button_b}]` (비동기 입력이므로
정적 타이밍 분석에서 제외, 회로 내부 2단 동기화로 별도 처리).
