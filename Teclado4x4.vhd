library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Teclado matricial 4x4 con FSM: ESCANEO -> CONFIRMAR -> SOLTAR
-- Entrega UN solo pulso key_valid por pulsacion, con el codigo correcto.
-- Columnas con pull-up (externo de 10k o weak pull-up de Quartus). Filas: poner 330 ohm en serie.
entity Teclado4x4 is
    Port (
        clk       : in  STD_LOGIC;                      -- 50 MHz
        rst       : in  STD_LOGIC;                      -- Activo en alto (igual que tus otros modulos)
        filas     : out STD_LOGIC_VECTOR (3 downto 0);
        columnas  : in  STD_LOGIC_VECTOR (3 downto 0);
        key_code  : out STD_LOGIC_VECTOR (3 downto 0);  -- 0-9, A=10, B=11, C=12, D=13, *=14, #=15
        key_valid : out STD_LOGIC                       -- 1 pulso por pulsacion
    );
end Teclado4x4;

architecture arch_Teclado4x4 of Teclado4x4 is
    type state_type is (ESCANEO, CONFIRMAR, SOLTAR);
    signal state : state_type := ESCANEO;

    constant SLOT     : integer := 50000;    -- 1 ms por fila
    constant MUESTREO : integer := 25000;    -- se lee a mitad del slot: columnas ya estables
    constant T_DEB    : integer := 500000;   -- 10 ms

    signal slot_cnt : integer range 0 to 50000  := 0;
    signal deb_cnt  : integer range 0 to 500000 := 0;
    signal fila     : integer range 0 to 3 := 0;

    signal col_s1, col_s2 : std_logic_vector(3 downto 0) := (others => '1');
    signal hay_tecla : std_logic;
    signal codigo    : std_logic_vector(3 downto 0);
    signal cand      : std_logic_vector(3 downto 0) := (others => '0');
begin
    -- Fila activa en bajo
    with fila select
        filas <= "1110" when 0,
                 "1101" when 1,
                 "1011" when 2,
                 "0111" when others;

    -- Decodificacion (con valores por defecto: sin latches)
    process(fila, col_s2)
    begin
        hay_tecla <= '1';
        codigo    <= "0000";
        case fila is
            when 0 =>
                case col_s2 is
                    when "1110" => codigo <= "0001";   -- 1
                    when "1101" => codigo <= "0010";   -- 2
                    when "1011" => codigo <= "0011";   -- 3
                    when "0111" => codigo <= "1010";   -- A
                    when others => hay_tecla <= '0';
                end case;
            when 1 =>
                case col_s2 is
                    when "1110" => codigo <= "0100";   -- 4
                    when "1101" => codigo <= "0101";   -- 5
                    when "1011" => codigo <= "0110";   -- 6
                    when "0111" => codigo <= "1011";   -- B
                    when others => hay_tecla <= '0';
                end case;
            when 2 =>
                case col_s2 is
                    when "1110" => codigo <= "0111";   -- 7
                    when "1101" => codigo <= "1000";   -- 8
                    when "1011" => codigo <= "1001";   -- 9
                    when "0111" => codigo <= "1100";   -- C
                    when others => hay_tecla <= '0';
                end case;
            when others =>
                case col_s2 is
                    when "1110" => codigo <= "1110";   -- *
                    when "1101" => codigo <= "0000";   -- 0
                    when "1011" => codigo <= "1111";   -- #
                    when "0111" => codigo <= "1101";   -- D
                    when others => hay_tecla <= '0';
                end case;
        end case;
    end process;

    -- FSM
    process(clk, rst)
    begin
        if rst = '1' then
            state <= ESCANEO; slot_cnt <= 0; deb_cnt <= 0; fila <= 0;
            cand <= (others => '0'); key_code <= (others => '0'); key_valid <= '0';
            col_s1 <= (others => '1'); col_s2 <= (others => '1');
        elsif rising_edge(clk) then
            col_s1 <= columnas;           -- sincronizador de 2 FF
            col_s2 <= col_s1;
            key_valid <= '0';

            case state is
                -- Barre las filas (1 ms c/u) y lee SOLO a mitad del slot
                when ESCANEO =>
                    if slot_cnt = MUESTREO and hay_tecla = '1' then
                        cand <= codigo; deb_cnt <= 0;
                        state <= CONFIRMAR;                 -- congela la fila
                    elsif slot_cnt = SLOT - 1 then
                        slot_cnt <= 0;
                        if fila = 3 then fila <= 0; else fila <= fila + 1; end if;
                    else
                        slot_cnt <= slot_cnt + 1;
                    end if;

                -- Espera 10 ms y verifica que SIGA la misma tecla (antirrebote real)
                when CONFIRMAR =>
                    if deb_cnt = T_DEB - 1 then
                        if hay_tecla = '1' and codigo = cand then
                            key_code  <= cand;
                            key_valid <= '1';               -- un solo pulso
                            deb_cnt   <= 0;
                            state     <= SOLTAR;
                        else
                            slot_cnt <= 0;
                            state    <= ESCANEO;            -- fue ruido
                        end if;
                    else
                        deb_cnt <= deb_cnt + 1;
                    end if;

                -- No acepta otra tecla hasta que se suelte 10 ms seguidos
                when SOLTAR =>
                    if hay_tecla = '1' then
                        deb_cnt <= 0;
                    elsif deb_cnt = T_DEB - 1 then
                        slot_cnt <= 0;
                        state    <= ESCANEO;
                    else
                        deb_cnt <= deb_cnt + 1;
                    end if;
            end case;
        end if;
    end process;
end arch_Teclado4x4;