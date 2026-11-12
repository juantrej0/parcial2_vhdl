library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.std_logic_textio.all; -- Necesario para imprimir std_logic en consola
use std.textio.all;

entity TbTeclado4x4 is 
end entity;

architecture sim of TbTeclado4x4 is
    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal filas, columnas : std_logic_vector(3 downto 0);
    signal key_code : std_logic_vector(3 downto 0);
    signal key_valid : std_logic;
    signal pres : std_logic := '0';
    signal pr, pc : integer range 0 to 3 := 0;   -- tecla fisica presionada (fila, columna)
begin
    DUT: entity work.Teclado4x4 port map (clk=>clk, rst=>rst, filas=>filas,
                                              columnas=>columnas, key_code=>key_code, key_valid=>key_valid);
    clk <= not clk after 10 ns;

    -- Simulación del hardware del teclado
    g: for c in 0 to 3 generate
        columnas(c) <= '0' when (pres = '1' and pc = c and filas(pr) = '0') else '1';
    end generate;

    stim: process
    begin
        rst <= '1'; wait for 1 us; rst <= '0';
        wait for 5 ms;
        pr <= 0; pc <= 0; pres <= '1'; wait for 45 ms;  -- tecla "1" sostenida 45 ms  -> 1 pulso
        pres <= '0';                    wait for 15 ms;
        pr <= 1; pc <= 0; pres <= '1'; wait for 30 ms;  -- tecla "4"                 -> 1 pulso
        pres <= '0';                    wait for 15 ms;
        pr <= 3; pc <= 1; pres <= '1'; wait for 3 ms;   -- ruido de 3 ms ("0")      -> 0 pulsos
        pres <= '0';                    wait for 15 ms;
        wait;
    end process;

    monitor: process(clk)
        variable L : line;
        variable n : integer := 0;
    begin
        if rising_edge(clk) and key_valid = '1' then
            n := n + 1;
            write(L, string'("key_valid #")); write(L, n);
            write(L, string'("  codigo=")); write(L, key_code);
            write(L, string'("  t=")); write(L, now);
            writeline(output, L);
        end if;
    end process;
end architecture;
