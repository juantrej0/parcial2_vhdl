library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity BandaTransportadora is
    Port ( 
        CLK   : in  STD_LOGIC;
        RST   : in  STD_LOGIC; 
        
        SW_FREQ_ON  : in  STD_LOGIC;                     
        SW_FREQ_SEL : in  STD_LOGIC_VECTOR (2 downto 1); 
        
        IR_PRES_PIN : in  STD_LOGIC; 
        IR_SIZE_PIN : in  STD_LOGIC; 
        COLOR_OUT   : in  STD_LOGIC; 
        
        TCS_S0, TCS_S1, TCS_S2, TCS_S3, TCS_OE : out STD_LOGIC;
        MOT_PWM, MOT_IN1, MOT_IN2, MOT_STBY : out STD_LOGIC;
        
        -- Solo 2 Servos ahora
        SERVO_ROJO, SERVO_VERDE : out STD_LOGIC;
        
        TECLADO_FILAS : out STD_LOGIC_VECTOR (3 downto 0);
        TECLADO_COLS  : in  STD_LOGIC_VECTOR (3 downto 0);
        DIS1, DIS2, DIS3, DIS4 : out STD_LOGIC_VECTOR (6 downto 0);
        DIS_EXTRA_DEC : out STD_LOGIC_VECTOR (7 downto 0);
        DIS_EXTRA_UNI : out STD_LOGIC_VECTOR (7 downto 0);
        RUTA_RP, RUTA_RG, RUTA_VP, RUTA_VG, RUTA_AP, RUTA_AG, RECHAZO : out STD_LOGIC;
        ERROR_LED : out STD_LOGIC
    );
end BandaTransportadora;

architecture arch of BandaTransportadora is

    signal pres_fisica, size_fisica : std_logic;
    signal color_detectado : std_logic_vector(1 downto 0);
    signal motor_en : std_logic;
    signal srv_rojo, srv_verde, srv_azul : std_logic;
    
    signal pieza_ok, tam_ok : std_logic;
    signal color_ok : std_logic_vector(1 downto 0);

    signal btn_r_falso, btn_v_falso, btn_a_falso : std_logic;
    signal ruta_rp_sig, ruta_rg_sig, ruta_vp_sig, ruta_vg_sig, ruta_ap_sig, ruta_ag_sig, rechazo_sig : std_logic;
    signal kp_code : std_logic_vector(3 downto 0);
    signal kp_valid : std_logic;
    
    signal modo_actual : std_logic_vector(3 downto 0) := "0001";
    signal modo_rf5, modo_nav : std_logic;
    signal nav_sel_sig : std_logic_vector(1 downto 0) := "00"; 
    
    signal total_piezas_sim : std_logic_vector(7 downto 0) := "00010100";
    signal disp_extra_data  : std_logic_vector(7 downto 0);

    component SystemOmega port (
        CLK, RST : in std_logic; BTN_R, BTN_A, BTN_V : in std_logic;
        FREQ_SEL : in std_logic_vector(2 downto 1); FREQ_ON, PRES_IN, SIZE_IN, MODE : in std_logic;
        NAV_SEL : in std_logic_vector(1 downto 0); NAV_EN : in std_logic;
        DIS1, DIS2, DIS3, DIS4 : out std_logic_vector(6 downto 0);
        FRECUENCIA, Led_CLK : out std_logic;
        RUTA_RP, RUTA_RG, RUTA_VP, RUTA_VG, RUTA_AP, RUTA_AG, RECHAZO : out std_logic
    ); end component;

    component Control_Linea port (
        clk, rst, encender, presencia, tamano : in std_logic;
        color_detectado : in std_logic_vector(1 downto 0);
        freq_sel : in std_logic_vector(2 downto 1);
        motor_enable, servo_rojo_en, servo_verde_en, servo_azul_en : out std_logic;
        guardar_delta, error_led, pieza_valida, tamano_valido : out std_logic;
        color_valido : out std_logic_vector(1 downto 0)
    ); end component;

    component Sensores_Infra port (
        clk, rst, ir_pres_raw, ir_size_raw : in std_logic;
        PRES_OUT, SIZE_OUT : out std_logic
    ); end component;

    component sensor_color port (
        clk, rst : in std_logic; color_out : in std_logic;
        s0, s1, s2, s3, oe : out std_logic;
        color_det : out std_logic_vector(1 downto 0);
        debug_latido : out std_logic
    ); end component;

    -- Componente ServoMotor modificado (solo 2 servos)
    component ServoMotor port (
        clk, rst : in std_logic;
        es_rojo, es_verde : in std_logic;
        PWM_Servo_Rojo, PWM_Servo_Verde : out std_logic
    ); end component;
    
    component MotorDC_banda port (
        clk, rst, encender : in std_logic;
        freq_sel : in std_logic_vector(2 downto 1);
        pwm_out, in1, in2, stby : out std_logic;
        led_estado : out std_logic
    ); end component;

    component displays_extra port (
        clk, rst : in std_logic;
        numero_bin : in std_logic_vector(7 downto 0);
        seg_decenas, seg_unidades : out std_logic_vector(7 downto 0)
    ); end component;

    component Teclado4x4 port (
        clk, rst : in STD_LOGIC;
        filas    : out STD_LOGIC_VECTOR (3 downto 0);
        columnas : in  STD_LOGIC_VECTOR (3 downto 0);
        key_code : out STD_LOGIC_VECTOR (3 downto 0);
        key_valid: out STD_LOGIC
    ); end component;

begin
    RUTA_RP <= ruta_rp_sig;
    RUTA_RG <= ruta_rg_sig;
    RUTA_VP <= ruta_vp_sig;
    RUTA_VG <= ruta_vg_sig;
    RUTA_AP <= ruta_ap_sig;
    RUTA_AG <= ruta_ag_sig;
    RECHAZO <= rechazo_sig;

    SENSORES_IR: Sensores_Infra port map (
        clk => CLK, rst => not RST, ir_pres_raw => IR_PRES_PIN, ir_size_raw => IR_SIZE_PIN,
        PRES_OUT => pres_fisica, SIZE_OUT => size_fisica
    );

    SENSOR_RGB: sensor_color port map (
        clk => CLK, rst => RST, color_out => COLOR_OUT,
        s0 => TCS_S0, s1 => TCS_S1, s2 => TCS_S2, s3 => TCS_S3, oe => TCS_OE,
        color_det => color_detectado, debug_latido => open
    );

    TECLADO: Teclado4x4 port map (
        clk => CLK, rst => RST,
        filas => TECLADO_FILAS, columnas => TECLADO_COLS,
        key_code => kp_code, key_valid => kp_valid
    );

    -- LÓGICA DE LAS TECLAS
    process(CLK, RST)
    begin
        if RST = '1' then 
            modo_actual <= "0001"; 
            nav_sel_sig <= "00";
        elsif rising_edge(CLK) then
            if kp_valid = '1' then
                case kp_code is
                    when "0001" => modo_actual <= "0001"; 
                    when "0010" => modo_actual <= "0010"; 
                    when "0011" => modo_actual <= "0011"; nav_sel_sig <= "00";
                    when "0100" => modo_actual <= "0011"; nav_sel_sig <= "01";
                    when "0101" => modo_actual <= "0011"; nav_sel_sig <= "10";
                    when "0110" => modo_actual <= "0011"; nav_sel_sig <= "11";
                    when "0111" => modo_actual <= "0100";
                    when others => null;
                end case;
            end if;
        end if;
    end process;
    
    modo_rf5 <= '1' when modo_actual = "0010" else '0';
    modo_nav <= '1' when modo_actual = "0011" else '0';

    -- SUPERVISOR
    SUPERVISOR: Control_Linea port map (
        clk => CLK, rst => RST,
        encender => SW_FREQ_ON, presencia => pres_fisica, 
        tamano => size_fisica, 
        color_detectado => color_detectado, 
        freq_sel => SW_FREQ_SEL,
        motor_enable => motor_en, 
        servo_rojo_en => srv_rojo,
        servo_verde_en => srv_verde, 
        servo_azul_en => srv_azul, -- Se queda interna, pero no se usa
        guardar_delta => open, error_led => ERROR_LED, 
        pieza_valida => pieza_ok, tamano_valido => tam_ok, color_valido => color_ok
    );

    btn_r_falso <= '0' when color_ok = "01" else '1';
    btn_v_falso <= '0' when color_ok = "10" else '1';
    btn_a_falso <= '0' when color_ok = "11" else '1';

    CEREBRO: SystemOmega port map (
        CLK => CLK, RST => not RST, 
        BTN_R => btn_r_falso, BTN_V => btn_v_falso, BTN_A => btn_a_falso,
        FREQ_SEL => SW_FREQ_SEL, FREQ_ON  => SW_FREQ_ON, 
        PRES_IN => pieza_ok, 
        SIZE_IN => tam_ok, 
        MODE    => modo_rf5, 
        NAV_EN  => modo_nav, 
        NAV_SEL => nav_sel_sig, 
        DIS1 => DIS1, DIS2 => DIS2, DIS3 => DIS3, DIS4 => DIS4,
        FRECUENCIA => open, Led_CLK => open,
        RUTA_RP => ruta_rp_sig, RUTA_RG => ruta_rg_sig, 
        RUTA_VP => ruta_vp_sig, RUTA_VG => ruta_vg_sig, 
        RUTA_AP => ruta_ap_sig, RUTA_AG => ruta_ag_sig, RECHAZO => rechazo_sig
    );

    MOTOR: MotorDC_banda port map (
        clk => CLK, rst => RST, encender => motor_en,          
        freq_sel => SW_FREQ_SEL, 
        pwm_out => MOT_PWM, in1 => MOT_IN1, in2 => MOT_IN2, stby => MOT_STBY,
        led_estado => open
    );

    -- INSTANCIACIÓN DE LOS 2 SERVOS
    SERVOS: ServoMotor port map (
        clk => CLK, rst => RST,
        es_rojo => srv_rojo, 
        es_verde => srv_verde,
        PWM_Servo_Rojo => SERVO_ROJO, 
        PWM_Servo_Verde => SERVO_VERDE
    );

    disp_extra_data <= total_piezas_sim when modo_actual = "0100" else "00000000";
    DISP_EXTRA: displays_extra port map (
        clk => CLK, rst => RST,
        numero_bin => disp_extra_data,
        seg_decenas => DIS_EXTRA_DEC,
        seg_unidades => DIS_EXTRA_UNI
    );

end arch;