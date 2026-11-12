library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity Control_Linea is
    generic (
        ESCALA         : integer := 1;
        -- Tiempos medidos con la banda a la velocidad "01" (1 Hz). Para las otras
        -- velocidades se escalan solos segun freq_sel (ver funcion escala_vel).
        AVANCE_CICLOS  : integer := 2500000;   -- presencia -> sensor de color   (50 ms a 1 Hz)
        VENTANA_CICLOS : integer := 15000000;  -- ventana de lectura de color    (300 ms a 1 Hz)
        DESVIO_CICLOS  : integer := 2500000    -- color decidido -> servo        (50 ms a 1 Hz)
    );
    Port ( 
        clk, rst : in STD_LOGIC;
        encender, presencia : in STD_LOGIC;
        tamano : in STD_LOGIC; 
        color_detectado : in STD_LOGIC_VECTOR(1 downto 0);
        freq_sel : in STD_LOGIC_VECTOR(2 downto 1);
        
        motor_enable, servo_rojo_en, servo_verde_en, servo_azul_en : out STD_LOGIC;
        guardar_delta, error_led : out STD_LOGIC;
        
        pieza_valida : out STD_LOGIC; 
        tamano_valido : out STD_LOGIC;
        color_valido : out STD_LOGIC_VECTOR(1 downto 0)
    );
end Control_Linea;

architecture arch of Control_Linea is
    type state_type is (DETENIDA, ESPERANDO_PIEZA, AVANZANDO, LEYENDO, CLASIFICANDO, DESVIANDO, FALLO);
    signal state : state_type := DETENIDA;

    -- Velocidad de la banda segun freq_sel (el tiempo es inversamente proporcional):
    --   "00" = 0.5 Hz (x2 tiempo)   "01" = 1 Hz (x1)   "10" = 2 Hz (/2)   "11" = 3 Hz (/3)
    -- Si tu mapeo es otro, solo cambia los casos de esta funcion.
    function escala_vel(base : integer; sel : std_logic_vector(2 downto 1)) return integer is
    begin
        case sel is
            when "00"   => return base * 2;
            when "01"   => return base;
            when "10"   => return base / 2;
            when "11"   => return base / 3;
            when others => return base;
        end case;
    end function;

    function piso1(x : integer) return integer is
    begin
        if x < 1 then return 1; else return x; end if;
    end function;
    
    signal timer : integer := 0;
    signal delay_servo : integer := 0;
    signal t_avance  : integer := 0;
    signal t_ventana : integer := 0;
    
    signal color_fijado : std_logic_vector(1 downto 0) := "00";
    signal tamano_fijado : std_logic := '0';
    
    -- Tiempos a 1 Hz (50 MHz)
    constant A_1HZ : integer := AVANCE_CICLOS  / ESCALA;
    constant V_1HZ : integer := VENTANA_CICLOS / ESCALA;
    constant D_1HZ : integer := DESVIO_CICLOS  / ESCALA;
    -- Minimo de ciclos que un color debe acumular en la ventana para contar (20 ms)
    constant T_MIN_VOTOS : integer := piso1(1000000 / ESCALA);
    constant T_SERVO   : integer := 15000000  / ESCALA;  -- 300 ms
    constant T_TIMEOUT : integer := 100000000 / ESCALA;  -- 2 s
    
    signal pres_s1, pres_s2 : std_logic;
    signal pres_pulse : std_logic;
    signal timeout_cnt : integer := 0;

    -- Ventana de captura de tamano: abierta mientras la pieza esta sobre presencia/tamano
    signal ventana_tam : std_logic := '0';

    -- Votos de color: ciclos que el sensor marco cada color durante la ventana
    signal votos_r, votos_g, votos_b : integer range 0 to 100000000 := 0;
begin
    -- Asignacion unica para evitar multiples drivers
    tamano_valido <= tamano_fijado;
    color_valido <= color_fijado;

    process(clk, rst)
    begin
        if rst = '1' then
            pres_s1 <= '0'; pres_s2 <= '0';
        elsif rising_edge(clk) then
            pres_s1 <= presencia; pres_s2 <= pres_s1;
        end if;
    end process;
    pres_pulse <= pres_s1 and (not pres_s2);

    process(clk, rst)
    begin
        if rst = '1' then
            state <= DETENIDA;
            timer <= 0; timeout_cnt <= 0; ventana_tam <= '0';
            motor_enable <= '0';
            servo_rojo_en <= '0'; servo_verde_en <= '0'; servo_azul_en <= '0';
            guardar_delta <= '0'; error_led <= '0';
            pieza_valida <= '0'; 
            tamano_fijado <= '0'; 
            color_fijado <= "00"; 
            votos_r <= 0; votos_g <= 0; votos_b <= 0;
            t_avance <= 0; t_ventana <= 0; delay_servo <= 0;
            
        elsif rising_edge(clk) then
            guardar_delta <= '0';
            pieza_valida <= '0'; -- Pulso por defecto
            
            case state is
                when DETENIDA =>
                    motor_enable <= '0';
                    if encender = '1' then
                        state <= ESPERANDO_PIEZA;
                    end if;
                    
                when ESPERANDO_PIEZA =>
                    motor_enable <= '1';
                    timeout_cnt <= 0;
                    color_fijado <= "00"; -- limpia el color anterior
                    
                    -- PRIORIDAD 1 y 2: presencia + tamano (sensores pegados)
                    if pres_pulse = '1' then
                        tamano_fijado <= tamano;   -- tamano se captura apenas llega la pieza
                        ventana_tam <= '1';        -- y sigue capturando mientras presencia = 1
                        -- Los tiempos se fijan UNA vez por pieza segun la velocidad actual
                        t_avance  <= escala_vel(A_1HZ, freq_sel);
                        t_ventana <= escala_vel(V_1HZ, freq_sel);
                        timer <= 0;
                        state <= AVANZANDO;
                    end if;

                when AVANZANDO =>
                    -- La pieza todavia va camino al sensor de color: NO se lee color.
                    motor_enable <= '1';
                    if timer >= t_avance then
                        timer <= 0;
                        votos_r <= 0; votos_g <= 0; votos_b <= 0;
                        state <= LEYENDO;
                    else
                        timer <= timer + 1;
                    end if;
                    
                when LEYENDO =>
                    -- PRIORIDAD 3: color. Durante toda la ventana se vota; gana el color
                    -- que mas tiempo marco el sensor (los instantes de transicion al
                    -- entrar/salir la pieza quedan con pocos votos y no deciden).
                    motor_enable <= '1';
                    case color_detectado is
                        when "01"   => votos_r <= votos_r + 1;
                        when "10"   => votos_g <= votos_g + 1;
                        when "11"   => votos_b <= votos_b + 1;
                        when others => null;
                    end case;

                    if timer >= t_ventana then
                        if votos_r > votos_g and votos_r > votos_b and votos_r >= T_MIN_VOTOS then
                            color_fijado <= "01";
                        elsif votos_g >= votos_b and votos_g >= votos_r and votos_g >= T_MIN_VOTOS then
                            color_fijado <= "10";   -- en empate verde/azul se prefiere verde
                        elsif votos_b > votos_g and votos_b >= votos_r and votos_b >= T_MIN_VOTOS then
                            color_fijado <= "11";
                        else
                            color_fijado <= "00";   -- sin color claro: la pieza no se desvia
                        end if;
                        pieza_valida <= '1';
                        state <= CLASIFICANDO;
                    else
                        timer <= timer + 1;
                    end if;
                    
                when CLASIFICANDO =>
                    -- Retardo hasta el servo: inversamente proporcional a la velocidad
                    delay_servo <= escala_vel(D_1HZ, freq_sel);
                    timer <= 0;
                    state <= DESVIANDO;
                    
                when DESVIANDO =>
                    motor_enable <= '1';
                    if timer < delay_servo then
                        timer <= timer + 1;
                    elsif timer < (delay_servo + T_SERVO) then
                        if color_fijado = "01" then servo_rojo_en <= '1';
                        elsif color_fijado = "10" then servo_verde_en <= '1';
                        elsif color_fijado = "11" then servo_azul_en <= '1';
                        end if;
                        if timer = delay_servo then
                            guardar_delta <= '1';
                        end if;
                        timer <= timer + 1;
                    else
                        servo_rojo_en <= '0'; servo_verde_en <= '0'; servo_azul_en <= '0';
                        state <= ESPERANDO_PIEZA;
                    end if;
                    
                when FALLO =>
                    motor_enable <= '0';
                    servo_rojo_en <= '0'; servo_verde_en <= '0'; servo_azul_en <= '0';
                    error_led <= '1';
                    if encender = '0' or pres_pulse = '1' then
                        error_led <= '0';
                        state <= DETENIDA;
                    end if;
            end case;

            -- Captura de tamano: 1 = pieza alta. Si el sensor alto se activa en algun
            -- momento mientras la pieza esta sobre presencia, la pieza es alta.
            if presencia = '0' then
                ventana_tam <= '0';          -- la pieza ya salio: se cierra la ventana
            elsif ventana_tam = '1' and tamano = '1' then
                tamano_fijado <= '1';
            end if;
            
            -- WATCHDOG DESACTIVADO PARA PRUEBAS
            -- if state = ESPERANDO_PIEZA and presencia = '1' then
            --    if timeout_cnt = T_TIMEOUT then state <= FALLO;
            --    else timeout_cnt <= timeout_cnt + 1; end if;
            -- end if;

            if encender = '0' and state /= FALLO then
                state <= DETENIDA;
                motor_enable <= '0';
                servo_rojo_en <= '0'; servo_verde_en <= '0'; servo_azul_en <= '0';
            end if;
        end if;
    end process;
end arch;