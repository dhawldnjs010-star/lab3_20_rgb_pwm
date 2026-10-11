// LAB3-20 · RGB LED PWM
// R/G/B 버튼으로 세 PWM duty를 독립적으로 바꾸고 네 개씩 묶인 RGB LED 핀에 출력한다.
// 하위 모듈: button_onepulse (2단 동기화 + 디바운스 원펄스), pwm_channel (레벨→threshold PWM)
// top 모듈: lab3_rgb_pwm

`timescale 1ns/1ps
module button_onepulse #(
    parameter integer STABLE_CYCLES = 1_000_000
) (
    input  wire clk,
    input  wire rst_p,
    input  wire button,
    output reg  pulse
);
    (* ASYNC_REG = "TRUE" *) reg button_meta;
    (* ASYNC_REG = "TRUE" *) reg button_sync;
    localparam integer COUNT_WIDTH = (STABLE_CYCLES < 2) ? 1 : $clog2(STABLE_CYCLES);
    reg [COUNT_WIDTH-1:0] stable_count;
    reg accepted;

    // 2단 플립플롭으로 비동기 버튼 입력을 clk 도메인에 동기화한다.
    always @(posedge clk or posedge rst_p) begin
        if (rst_p) begin
            button_meta <= 1'b0;
            button_sync <= 1'b0;
        end else begin
            button_meta <= button;
            button_sync <= button_meta;
        end
    end

    // 동기화된 값이 STABLE_CYCLES 동안 유지되어야 accepted를 갱신하고,
    // 값이 바뀌는 순간(눌림)에만 1클록 폭의 pulse를 만든다(디바운스 + 원펄스).
    always @(posedge clk or posedge rst_p) begin
        if (rst_p) begin
            stable_count <= {COUNT_WIDTH{1'b0}};
            accepted <= 1'b0;
            pulse <= 1'b0;
        end else begin
            pulse <= 1'b0;
            if (button_sync == accepted) begin
                stable_count <= {COUNT_WIDTH{1'b0}};
            end else if (stable_count == STABLE_CYCLES - 1) begin
                stable_count <= {COUNT_WIDTH{1'b0}};
                accepted <= button_sync;
                pulse <= button_sync;
            end else begin
                stable_count <= stable_count + 1'b1;
            end
        end
    end
endmodule


`timescale 1ns/1ps
module pwm_channel #(
    parameter integer PERIOD_CYCLES = 50_000,
    parameter integer LEVELS = 10
) (
    input  wire clk,
    input  wire rst_p,
    input  wire [3:0] level,
    output reg  pwm
);
    localparam integer COUNT_WIDTH = (PERIOD_CYCLES < 2) ? 1 : $clog2(PERIOD_CYCLES);
    reg [COUNT_WIDTH-1:0] count;
    integer threshold;

    // level(0..LEVELS)을 PERIOD_CYCLES 기준 threshold로 환산한다.
    // level >= LEVELS는 항상 켜짐(100%)으로 포화시킨다.
    always @* begin
        if (level >= LEVELS)
            threshold = PERIOD_CYCLES;
        else
            threshold = (PERIOD_CYCLES * level) / LEVELS;
    end

    // 자유 실행 카운터: count < threshold 구간에서 pwm=1.
    always @(posedge clk or posedge rst_p) begin
        if (rst_p) begin
            count <= {COUNT_WIDTH{1'b0}};
            pwm <= 1'b0;
        end else begin
            pwm <= (count < threshold);
            if (count == PERIOD_CYCLES - 1)
                count <= {COUNT_WIDTH{1'b0}};
            else
                count <= count + 1'b1;
        end
    end
endmodule


`timescale 1ns/1ps
module lab3_rgb_pwm #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer PWM_HZ = 1_000,
    parameter integer LEVELS = 10,
    parameter integer DEBOUNCE_CYCLES = 1_000_000
) (
    input  wire clk_50mhz,
    input  wire rst_p,
    input  wire button_r,
    input  wire button_g,
    input  wire button_b,
    output wire [3:0] led_r,
    output wire [3:0] led_g,
    output wire [3:0] led_b
);
    wire press_r, press_g, press_b;
    wire pwm_r, pwm_g, pwm_b;
    reg [3:0] level_r, level_g, level_b;

    button_onepulse #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) u_button_r (
        .clk(clk_50mhz), .rst_p(rst_p), .button(button_r), .pulse(press_r));
    button_onepulse #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) u_button_g (
        .clk(clk_50mhz), .rst_p(rst_p), .button(button_g), .pulse(press_g));
    button_onepulse #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) u_button_b (
        .clk(clk_50mhz), .rst_p(rst_p), .button(button_b), .pulse(press_b));

    // 버튼 원펄스마다 레벨을 1씩 증가시키고 LEVELS에서 0으로 순환한다.
    always @(posedge clk_50mhz or posedge rst_p) begin
        if (rst_p) begin
            level_r <= 0; level_g <= 0; level_b <= 0;
        end else begin
            if (press_r) level_r <= (level_r == LEVELS) ? 0 : level_r + 1'b1;
            if (press_g) level_g <= (level_g == LEVELS) ? 0 : level_g + 1'b1;
            if (press_b) level_b <= (level_b == LEVELS) ? 0 : level_b + 1'b1;
        end
    end

    pwm_channel #(.PERIOD_CYCLES(CLK_HZ / PWM_HZ), .LEVELS(LEVELS)) u_pwm_r
        (.clk(clk_50mhz), .rst_p(rst_p), .level(level_r), .pwm(pwm_r));
    pwm_channel #(.PERIOD_CYCLES(CLK_HZ / PWM_HZ), .LEVELS(LEVELS)) u_pwm_g
        (.clk(clk_50mhz), .rst_p(rst_p), .level(level_g), .pwm(pwm_g));
    pwm_channel #(.PERIOD_CYCLES(CLK_HZ / PWM_HZ), .LEVELS(LEVELS)) u_pwm_b
        (.clk(clk_50mhz), .rst_p(rst_p), .level(level_b), .pwm(pwm_b));

    assign led_r = {4{pwm_r}};
    assign led_g = {4{pwm_g}};
    assign led_b = {4{pwm_b}};
endmodule
