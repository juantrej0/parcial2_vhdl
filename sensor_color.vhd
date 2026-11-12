library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity sensor_color is
    generic (
        VENTANA   : integer := 500_000; -- 10 ms a 50 MHz por filtro (ronda R-G-B = 30 ms)
        UMBRAL    : integer := 10;      -- flancos minimos del canal ganador
        SETTLE    : integer := 100_000; -- 2 ms ignorados tras cambiar de filtro
        TOL_ABS   : integer := 4;       -- tolerancia absoluta (flancos) para considerar "fondo"

        GAIN_R    : integer := 16;
        GAIN_G    : integer := 16;
        GAIN_B    : integer := 16;
		  
        -- Margen que debe superar el canal ganador sobre los otros, en 1/16 (17 = +6.25 %)
        MARGEN    : integer := 17;
        -- Rondas seguidas viendo "pieza" antes de recalibrar el fondo (150 rondas = ~4.5 s).
        -- Debe ser MAYOR que el tiempo que una pieza real tarda en pasar frente al sensor.
        RONDAS_PEGADO : integer := 150
    );
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;  -- Activo en alto
        color_out   : in  std_logic;
        s0, s1      : out std_logic;
        s2, s3      : out std_logic;
        oe          : out std_logic;
        color_det   : out std_logic_vector(1 downto 0);
        debug_latido: out std_logic 
    );
end sensor_color;

architecture arch_sensor_color of sensor_color is
    constant N_CALIB   : integer := 16;  -- rondas promediadas para el fondo (~480 ms)
    constant DESCARTE  : integer := 4;   -- rondas iniciales descartadas (~120 ms)
    constant TRACK_DIV : integer := 8;   -- el fondo sigue 1/8 de la diferencia por ronda

    function piso1(x : integer) return integer is
    begin
        if x < 1 then return 1; else return x; end if;
    end function;

    signal col_s1, col_s2, col_prev : std_logic := '0';
    signal cnt_ventana : integer range 0 to VENTANA := 0;
    signal cnt_flancos : integer range 0 to 4095 := 0;
    
    signal filtro_actual : integer range 0 to 2 := 0; 
    signal cnt_r, cnt_g, cnt_b : integer range 0 to 4095 := 0;
    signal ronda_lista : std_logic := '0';

    -- Calibracion de fondo
    signal calib_rondas : integer range 0 to 255 := 0;
    signal sum_r, sum_g, sum_b : integer range 0 to 65535 := 0;
    signal base_r, base_g, base_b : integer range 1 to 4095 := 1;
    signal calibrado : std_logic := '0';
    signal ocupado_rondas : integer range 0 to 100000 := 0;  -- rondas seguidas viendo pieza

    signal color_reg : std_logic_vector(1 downto 0) := "00";

    -- Comparaciones (todas combinacionales sobre contadores ya estables)
    signal fondo_r, fondo_g, fondo_b : boolean;
    signal r_gt_g, r_gt_b, g_gt_r, g_gt_b, b_gt_r, b_gt_g : boolean;
    
    -- Contador independiente para el latido (25 Millones de ciclos = 0.5 seg)
    signal latido_cont : integer range 0 to 25000000 := 0;
    signal latido_led  : std_logic := '0';
begin
    s0 <= '1'; 
    s1 <= '0'; 
    oe <= '0'; 

    -- Generador de Latido Lento (Visible al ojo humano)
    process(clk, rst)
    begin
        if rst = '1' then
            latido_cont <= 0;
            latido_led <= '0';
        elsif rising_edge(clk) then
            if latido_cont = 24999999 then
                latido_cont <= 0;
                latido_led <= not latido_led;
            else
                latido_cont <= latido_cont + 1;
            end if;
        end if;
    end process;
    debug_latido <= latido_led;

    -- Multiplexor de filtros
    process(filtro_actual)
    begin
        case filtro_actual is
            when 0 => s2 <= '0'; s3 <= '0'; -- Rojo
            when 1 => s2 <= '1'; s3 <= '1'; -- Verde
            when 2 => s2 <= '0'; s3 <= '1'; -- Azul
            when others => s2 <= '0'; s3 <= '0';
        end case;
    end process;

    -- Sincronizador
    process(clk, rst)
    begin
        if rst = '1' then
            col_s1 <= '0'; col_s2 <= '0'; col_prev <= '0';
        elsif rising_edge(clk) then
            col_s1 <= color_out; col_s2 <= col_s1; col_prev <= col_s2;
        end if;
    end process;

    -- Medicion de frecuencias (una ventana por filtro)
    process(clk, rst)
    begin
        if rst = '1' then
            cnt_ventana <= 0;
            cnt_flancos <= 0;
            cnt_r <= 0; cnt_g <= 0; cnt_b <= 0;
            filtro_actual <= 0;
            ronda_lista <= '0';
        elsif rising_edge(clk) then
            ronda_lista <= '0';
            if cnt_ventana = VENTANA - 1 then
                cnt_ventana <= 0;
                
                if filtro_actual = 0 then
                    cnt_r <= cnt_flancos; filtro_actual <= 1;
                elsif filtro_actual = 1 then
                    cnt_g <= cnt_flancos; filtro_actual <= 2;
                else
                    cnt_b <= cnt_flancos; filtro_actual <= 0;
                    ronda_lista <= '1';  -- ronda R-G-B completa
                end if;
                cnt_flancos <= 0;
            else
                cnt_ventana <= cnt_ventana + 1;
                -- Se ignora el tiempo de asentamiento tras el cambio de filtro
                if cnt_ventana >= SETTLE and col_s2 = '1' and col_prev = '0' and cnt_flancos < 1500 then
                    cnt_flancos <= cnt_flancos + 1;
                end if;
            end if;
        end if;
    end process;

    fondo_r <= abs(cnt_r - base_r) <= (base_r / 8) + TOL_ABS;
    fondo_g <= abs(cnt_g - base_g) <= (base_g / 8) + TOL_ABS;
    fondo_b <= abs(cnt_b - base_b) <= (base_b / 8) + TOL_ABS;

 
    r_gt_g <= (cnt_r * base_g * GAIN_R * 16) > (cnt_g * base_r * GAIN_G * MARGEN);
    r_gt_b <= (cnt_r * base_b * GAIN_R * 16) > (cnt_b * base_r * GAIN_B * MARGEN);
    g_gt_r <= (cnt_g * base_r * GAIN_G * 16) > (cnt_r * base_g * GAIN_R * MARGEN);
    g_gt_b <= (cnt_g * base_b * GAIN_G * 16) > (cnt_b * base_g * GAIN_B * MARGEN);
    b_gt_r <= (cnt_b * base_r * GAIN_B * 16) > (cnt_r * base_b * GAIN_R * MARGEN);
    b_gt_g <= (cnt_b * base_g * GAIN_B * 16) > (cnt_g * base_b * GAIN_G * MARGEN);

    -- Calibracion, seguimiento del fondo y decision (una vez por ronda completa)
    process(clk, rst)
    begin
        if rst = '1' then
            calib_rondas <= 0;
            sum_r <= 0; sum_g <= 0; sum_b <= 0;
            base_r <= 1; base_g <= 1; base_b <= 1;
            calibrado <= '0';
            ocupado_rondas <= 0;
            color_reg <= "00";
        elsif rising_edge(clk) then
            if ronda_lista = '1' then
                if calibrado = '0' then
                    color_reg <= "00";  -- calibrando: sin color
                    ocupado_rondas <= 0;
                    if calib_rondas < DESCARTE then
                        calib_rondas <= calib_rondas + 1;
                    elsif calib_rondas < DESCARTE + N_CALIB then
                        sum_r <= sum_r + cnt_r;
                        sum_g <= sum_g + cnt_g;
                        sum_b <= sum_b + cnt_b;
                        calib_rondas <= calib_rondas + 1;
                    else
                        base_r <= piso1(sum_r / N_CALIB);
                        base_g <= piso1(sum_g / N_CALIB);
                        base_b <= piso1(sum_b / N_CALIB);
                        calibrado <= '1';
                    end if;
                else
                    if fondo_r and fondo_g and fondo_b then
                        color_reg <= "00";   -- solo fondo: no hay pieza
                        ocupado_rondas <= 0;
                        -- Seguimiento lento del fondo (deriva por temperatura / luz)
                        base_r <= piso1(base_r + (cnt_r - base_r) / TRACK_DIV);
                        base_g <= piso1(base_g + (cnt_g - base_g) / TRACK_DIV);
                        base_b <= piso1(base_b + (cnt_b - base_b) / TRACK_DIV);
                    else
                        -- Se ve "pieza": si dura demasiado, el fondo cambio -> recalibrar
                        if ocupado_rondas < RONDAS_PEGADO then
                            ocupado_rondas <= ocupado_rondas + 1;
                        else
                            calibrado <= '0';
                            calib_rondas <= 0;
                            sum_r <= 0; sum_g <= 0; sum_b <= 0;
                            ocupado_rondas <= 0;
                        end if;

                        if r_gt_g and r_gt_b and cnt_r > UMBRAL then
                            color_reg <= "01";   -- Rojo
                        elsif g_gt_r and g_gt_b and cnt_g > UMBRAL then
                            color_reg <= "10";   -- Verde
                        elsif b_gt_r and b_gt_g and cnt_b > UMBRAL then
                            color_reg <= "11";   -- Azul
                        else
                            color_reg <= "00";   -- pieza sin color claro
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    color_det <= color_reg;

end arch_sensor_color;