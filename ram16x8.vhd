library IEEE;
use IEEE.std_logic_1164.ALL;
use IEEE.numeric_std.all;

entity ram16x8 is
    port (
	 --- Inputs
        Clock   : in  std_logic;
		  adress : in std_logic_vector(3 downto 0);
		  data_in: in std_logic_vector(7 downto 0);
		  WE : in std_logic;
    ---Outputs    
		  data_out  : out  std_logic_vector(7 downto 0)
		  );
end ram16x8;


architecture arch_ram16x8 of ram16x8 is

	type RAM_type is array (0 to 15) of std_logic_vector(7 downto 0);
	signal RAM : RAM_type;

    begin

	 MEMORY : PROCESS (clock)
		begin
		if(clock'event and clock ='1')then
			if (WE = '1') then
			RAM(to_integer(unsigned(adress))) <= data_in;
			else 
			data_out <= RAM(to_integer(unsigned(adress)));
			end if;
		end if;
		end process;
end arch_ram16x8;