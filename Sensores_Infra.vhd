library IEEE;
use IEEE.std_logic_1164.ALL;

entity Sensores_Infra is
    port ( 
        clk         : in  STD_LOGIC;
        rst         : in  STD_LOGIC; -- Activo en bajo (0 resetea, 1 funciona)
        
        -- Entradas crudas de los sensores
        ir_pres_raw : in  STD_LOGIC;
        ir_size_raw : in  STD_LOGIC;
        
        -- Salidas procesadas
        PRES_OUT    : out STD_LOGIC;
        SIZE_OUT    : out STD_LOGIC
    );
end Sensores_Infra;

architecture arch_Sensores_Infra of Sensores_Infra is

    component DflipFlop
        port (
            Clock          : in  std_logic;
            Reset, Preset  : in std_logic;
            D, EN          : in std_logic;
            Q, Qn          : out std_logic
        );
    end component;

    -- Señales internas
    signal pres_s1, pres_s2 : std_logic;
    signal size_s1, size_s2 : std_logic;
    
    -- SEÑALES INVERTIDAS (Para arreglar el problema de que se apagan al acercar)
    signal pres_invertida : std_logic;
    signal size_invertida : std_logic;

begin

    -- Invertimos la señal del sensor: 
    -- Si el sensor manda '0' (objeto detectado), se convierte en '1'.
    pres_invertida <= not ir_pres_raw;
    size_invertida <= not ir_size_raw;

    -- =========================================================
    -- Sincronizador para PRESENCIA (2 FF en cascada)
    -- =========================================================
    FF_P1: DflipFlop port map (
        Clock => clk, 
        Reset => rst, -- ¡CORREGIDO! Ahora rst es 1 para funcionar y 0 para resetear
        Preset => '1', 
        D => pres_invertida, -- Usamos la señal ya invertida
        EN => '1', 
        Q => pres_s1, 
        Qn => open
    );

    FF_P2: DflipFlop port map (
        Clock => clk, 
        Reset => rst, 
        Preset => '1', 
        D => pres_s1, 
        EN => '1', 
        Q => pres_s2, 
        Qn => open
    );

    PRES_OUT <= pres_s2;

    -- =========================================================
    -- Sincronizador para TAMAÑO (2 FF en cascada)
    -- =========================================================
    FF_S1: DflipFlop port map (
        Clock => clk, 
        Reset => rst, 
        Preset => '1', 
        D => size_invertida, -- Usamos la señal ya invertida
        EN => '1', 
        Q => size_s1, 
        Qn => open
    );

    FF_S2: DflipFlop port map (
        Clock => clk, 
        Reset => rst, 
        Preset => '1', 
        D => size_s1, 
        EN => '1', 
        Q => size_s2, 
        Qn => open
    );

    -- =========================================================
    -- MAGIA: El "Registro de Memoria" del Tamaño
    -- =========================================================
    FF_MEMORIA: DflipFlop port map (
        Clock => clk, 
        Reset => rst, 
        Preset => '1', 
        D => size_s2,       
        EN => pres_s2,      
        Q => SIZE_OUT,      
        Qn => open
    );

end arch_Sensores_Infra;