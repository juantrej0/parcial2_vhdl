library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Testbench para MotorDC_FSM: mira las ondas en ModelSim (Add Wave).
-- Reloj real de 50 MHz. Corre ~15 ms (Run -all o "run 15 ms").
entity tbMotorDC_banda is
end entity;

architecture sim of tbMotorDC_banda is
    signal clk      : std_logic := '0';
    signal rst      : std_logic := '1';              -- activo en alto: empieza en reset
    signal encender : std_logic := '0';
    signal freq_sel : std_logic_vector(1 downto 0) := "00";
    signal pwm_out, in1, in2, stby, led_estado : std_logic;
begin
    DUT: entity work.MotorDC_banda
        port map (clk => clk, rst => rst, encender => encender, freq_sel => freq_sel,
                  pwm_out => pwm_out, in1 => in1, in2 => in2,
                  stby => stby, led_estado => led_estado);

    clk <= not clk after 10 ns;   -- 50 MHz

    estimulo: process
    begin
        rst <= '1';  wait for 1 us;       -- reset
        rst <= '0';  wait for 1 us;       -- motor DETENIDO (in1=in2=0, pwm=0)
        encender <= '1';                  -- debe pasar a GIRANDO (in1=1, in2=0)
        freq_sel <= "00"; wait for 3 ms;  -- 25 %
        freq_sel <= "01"; wait for 3 ms;  -- 50 %
        freq_sel <= "10"; wait for 3 ms;  -- 75 %
        freq_sel <= "11"; wait for 3 ms;  -- 100 %
        encender <= '0';  wait for 2 ms;  -- debe volver a DETENIDO
        wait;
    end process;
end architecture;
