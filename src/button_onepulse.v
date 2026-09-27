`timescale 1ns/1ps

// LAB3-20 · button_onepulse (비동기 버튼 2단 동기화 + 디바운스 원펄스)
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
