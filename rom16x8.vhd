library IEEE;
use IEEE.std_logic_1164.ALL;
use IEEE.numeric_std.all;

entity rom16x8 is
    port (
	 --- Inputs
        Clock   : in  std_logic;
		  adress : in std_logic_vector(3 downto 0);
    ---Outputs    
		  data_out  : out  std_logic_vector(7 downto 0)
		  );
end rom16x8;


architecture arch_rom16x8 of rom16x8 is
    type ROM_type is array (0 to 15) of std_logic_vector(7 downto 0);
    
    constant ROM : ROM_type := (
        0  => "11000000", -- 0
        1  => "11111001", -- 1
        2  => "10100100", -- 2
        3  => "10110000", -- 3
        4  => "10011001", -- 4
        5  => "10010010", -- 5
        6  => "10000010", -- 6
        7  => "11111000", -- 7
        8  => "10000000", -- 8
        9  => "10010000", -- 9
        10 => "10001000", -- A 
        11 => "10000011", -- b
        12 => "11000110", -- C
        13 => "10100001", -- d
        14 => "10000110", -- E
        15 => "10001110"  -- F
    );
begin
    MEMORY : PROCESS (clock)
    begin
        if(clock'event and clock ='1')then
            data_out <= ROM (to_integer(unsigned(adress)));
        end if;
    end process;
end arch_rom16x8;
	
