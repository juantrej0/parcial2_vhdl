library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity MotorDC_banda is
    Port ( 
        clk         : in STD_LOGIC;
        rst         : in STD_LOGIC; -- Activo en alto
        encender    : in STD_LOGIC; -- Switch para encender/apagar (1=On, 0=Off)
        freq_sel    : in STD_LOGIC_VECTOR (1 downto 0); -- Velocidad (2 bits)
        
        -- Salidas al TB6612
        pwm_out     : out STD_LOGIC;
        in1, in2    : out STD_LOGIC;
        stby        : out STD_LOGIC;
        
        -- LED de debug (opcional)
        led_estado  : out STD_LOGIC
    );
end MotorDC_banda;

architecture arch_MotorDC_banda of MotorDC_banda is
    -- 1. DEFINICIÓN DE ESTADOS
    type state_type is (DETENIDO, GIRANDO);
    signal state : state_type := DETENIDO;

    -- 2. SEÑALES PARA EL PWM (1 kHz)
    signal contador_pwm : integer range 0 to 50000 := 0;
    signal duty         : integer range 0 to 50000 := 0;
    
    -- 3. SEÑAL INTERNA PARA EL PWM
    signal pwm_interno  : std_logic := '0';
begin
    -- Lógica combinacional para seleccionar la velocidad (Duty Cycle)
    process(freq_sel)
    begin
        case freq_sel is
            when "00" => duty <= 12500; -- 25%
            when "01" => duty <= 25000; -- 50%
            when "10" => duty <= 37500; -- 75%
            when "11" => duty <= 50000; -- 100%
            when others => duty <= 0;
        end case;
    end process;

    -- Generador de PWM constante
    process(clk, rst)
    begin
        if rst = '1' then
            contador_pwm <= 0;
            pwm_interno <= '0';
        elsif rising_edge(clk) then
            if contador_pwm < 49999 then 
                contador_pwm <= contador_pwm + 1;
            else 
                contador_pwm <= 0; 
            end if;
            
            if contador_pwm < duty then
                pwm_interno <= '1';
            else
                pwm_interno <= '0';
            end if;
        end if;
    end process;

   
    process(clk, rst)
    begin
        if rst = '1' then
            state <= DETENIDO;
        elsif rising_edge(clk) then
            case state is
                when DETENIDO =>
                    if encender = '1' then
                        state <= GIRANDO;
                    else
                        state <= DETENIDO;
                    end if;
                    
                when GIRANDO =>
                    if encender = '0' then
                        state <= DETENIDO;
                    else
                        state <= GIRANDO;
                    end if;
                    
                when others =>
                    state <= DETENIDO;
            end case;
        end if;
    end process;

    -- Lógica de salida hacia el TB6612 (Depende del Estado)
    process(state, pwm_interno)
    begin
        -- Valores por defecto (Frenado)
        in1 <= '0';
        in2 <= '0';
        pwm_out <= '0';
        stby <= '1'; -- Mantener el chip despierto
        led_estado <= '0';
        
        if state = GIRANDO then
            in1 <= '1';        -- Dirección adelante
            in2 <= '0';
            pwm_out <= pwm_interno; -- Aplicar la velocidad
            led_estado <= '1'; -- LED encendido indica motor girando
        else
            -- Estado DETENIDO (Freno activo en TB6612: IN1=0, IN2=0)
            in1 <= '0';
            in2 <= '0';
            pwm_out <= '0';
            led_estado <= '0';
        end if;
    end process;
end arch_MotorDC_banda;