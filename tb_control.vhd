library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.std_logic_textio.all; -- ¡NUEVO! Para poder imprimir std_logic
use std.textio.all;

entity tb_control is end entity;

architecture sim of tb_control is
    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal encender, presencia : std_logic := '0';
    signal color : std_logic_vector(1 downto 0) := "00";
    signal fsel  : std_logic_vector(2 downto 1) := "01";
    signal motor, s_r, s_v, s_a, guardar, err, pcon : std_logic;
    constant T : time := 20 ns;
    constant ESC : integer := 1000;   -- tiempos /1000 para simular rapido
begin
    -- ¡CORREGIDO! Control_Linea con guion bajo
    DUT: entity work.Control_Linea generic map (ESCALA => ESC)
        port map (clk=>clk, rst=>rst, encender=>encender, presencia=>presencia,
                  color_detectado=>color, freq_sel=>fsel,
                  motor_enable=>motor, servo_rojo_en=>s_r, servo_verde_en=>s_v, servo_azul_en=>s_a,
                  guardar_delta=>guardar, error_led=>err, pres_controlada=>pcon);
                  
    clk <= not clk after T/2;

    mon: process(motor, s_r, s_v, s_a, guardar, err, pcon)
        variable L : line;
    begin
        write(L, string'("t=")); write(L, now / 1 us); write(L, string'(" us  motor="));
        write(L, motor); write(L, string'(" pres_ctrl=")); write(L, pcon);
        write(L, string'(" servoR=")); write(L, s_r);
        write(L, string'(" servoV=")); write(L, s_v);
        write(L, string'(" servoA=")); write(L, s_a);
        write(L, string'(" guardar=")); write(L, guardar);
        write(L, string'(" error=")); write(L, err);
        writeline(output, L);
    end process;

    stim: process
        variable L : line;
        procedure msg(s : string) is
        begin
            write(L, string'("--- ")); write(L, s); writeline(output, L);
        end procedure;
    begin
        rst <= '1'; wait for T*5; rst <= '0';

        msg("A) encender=1, pieza VERDE (color=10), freq_sel=01");
        encender <= '1'; wait for T*10;
        color <= "10";
        presencia <= '1'; wait for T*8000;     -- pieza 160 us en el IR
        presencia <= '0'; wait for T*30000;    -- tiempo para que termine el desvio
        msg("FIN A: debe haber salido UN pulso 'guardar' y servoV=1 por 300 us (15000 ciclos)");

        msg("B) pieza ROJA y se APAGA el switch en pleno desvio");
        color <= "01";
        presencia <= '1'; wait for T*3000; presencia <= '0';
        wait for T*7000;                       -- ya estamos dentro de DESVIANDO
        encender <= '0'; wait for T*100;
        msg("FIN B: motor debe quedar 0 y servoR 0");
        wait for T*100;

        msg("C) pieza ATRAPADA en el sensor (presencia fija) -> ERROR");
        encender <= '1'; wait for T*10;
        presencia <= '1'; wait for T*140000;   -- se queda pegada > 2 s escalado (100000 ciclos)
        msg("FIN C: error_led debe estar en 1 y motor en 0");
        presencia <= '0'; encender <= '0'; wait for T*10;
        msg("FIN D: apagar encender limpia el error");
        wait;
    end process;
end architecture;
