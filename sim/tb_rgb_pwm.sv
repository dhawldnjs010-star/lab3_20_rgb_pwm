// LAB3-20 · RGB LED PWM 테스트벤치
// 축소 파라미터(CLK_HZ=1000, PWM_HZ=100 → PERIOD_CYCLES=10, LEVELS=10)로
// R=20%,G=50%,B=80% duty와 R 채널만 한 단계 증가하는 조건을 자기검사한다.

`timescale 1ns/1ps
module tb_rgb_pwm;
    reg clk_50mhz = 0, rst_p = 1, button_r = 0, button_g = 0, button_b = 0;
    wire [3:0] led_r, led_g, led_b;
    integer checks = 0, i, hr, hg, hb;

    always #10 clk_50mhz = ~clk_50mhz; // 20ns 주기(50MHz 상당)

    lab3_rgb_pwm #(
        .CLK_HZ(1000), .PWM_HZ(100), .LEVELS(10), .DEBOUNCE_CYCLES(2)
    ) dut (
        .clk_50mhz(clk_50mhz), .rst_p(rst_p),
        .button_r(button_r), .button_g(button_g), .button_b(button_b),
        .led_r(led_r), .led_g(led_g), .led_b(led_b)
    );

    task press_r; begin
        button_r = 1; repeat (6) @(posedge clk_50mhz);
        button_r = 0; repeat (6) @(posedge clk_50mhz);
    end endtask
    task press_g; begin
        button_g = 1; repeat (6) @(posedge clk_50mhz);
        button_g = 0; repeat (6) @(posedge clk_50mhz);
    end endtask
    task press_b; begin
        button_b = 1; repeat (6) @(posedge clk_50mhz);
        button_b = 0; repeat (6) @(posedge clk_50mhz);
    end endtask

    // 한 PWM 주기(10클록) 동안 각 LED의 HIGH 샘플 수를 세어 기대 duty와 비교한다.
    task measure(input integer er, input integer eg, input integer eb, input integer step);
        begin
            wait (dut.u_pwm_r.count == 0);
            hr = 0; hg = 0; hb = 0;
            for (i = 0; i < 10; i = i + 1) begin
                @(posedge clk_50mhz); #1;
                hr = hr + led_r[0];
                hg = hg + led_g[0];
                hb = hb + led_b[0];
            end
            if (hr !== er || hg !== eg || hb !== eb) begin
                $fatal(1, "FAIL: check %0d expected R=%0d G=%0d B=%0d got R=%0d G=%0d B=%0d",
                       step, er, eg, eb, hr, hg, hb);
            end
            checks = checks + 1;
            $display("PASS: check %0d duty R=%0d/10 G=%0d/10 B=%0d/10 (level_r=%0d level_g=%0d level_b=%0d)",
                      step, hr, hg, hb, dut.level_r, dut.level_g, dut.level_b);
        end
    endtask

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_rgb_pwm);

        repeat (3) @(posedge clk_50mhz);
        rst_p = 0;

        // R을 2번, G를 5번, B를 8번 눌러 level_r=2(20%), level_g=5(50%), level_b=8(80%)로 설정.
        repeat (2) press_r();
        repeat (5) press_g();
        repeat (8) press_b();
        measure(2, 5, 8, 1);

        // R만 한 번 더 눌러 level_r=3(30%)으로, G/B는 그대로인지 확인.
        press_r();
        measure(3, 5, 8, 2);

        $display("LAB3_RGB_PWM_PASS checks=%0d", checks);
        $display("TOTAL: %0d checks passed", checks);
        $finish;
    end

    initial begin
        #30000;
        $fatal(1, "TIMEOUT: simulation did not finish in time");
    end
endmodule
