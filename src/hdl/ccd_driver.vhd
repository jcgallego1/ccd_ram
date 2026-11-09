----------------------------------------------------------------------------------
-- Module Name: ccd_clock - Behavioral
-- Description: Controlador de sincronización para CCD Lineal TCD1304
--              con tiempo de integración parametrizable y señales de sincronía
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ccd_clock is
    Generic (
        CLK_FREQ_HZ     : integer := 100_000_000; -- Frecuencia reloj principal (ej. 100 MHz)
        PHIM_FREQ_HZ    : integer := 2_000_000;   -- Frecuencia phiM para el CCD (2 MHz)
        DEFAULT_T_INT   : integer := 20_000       -- Tiempo de integración por defecto (en ciclos phiM)
    );
    Port (
        clk             : in  STD_LOGIC;
        rst_n             : in  STD_LOGIC;
        
        -- Variable única de control de tiempo de integración / exposición (en ciclos de phiM)
        i_t_int_cycles  : in  STD_LOGIC_VECTOR(31 downto 0);
        
        -- Salidas físicas hacia el CCD TCD1304
        fim             : out STD_LOGIC; -- Master Clock (phiM)
        clk_o           : out STD_LOGIC; -- Réplica de phiM
        sh              : out STD_LOGIC; -- Shift Pulse
        icg             : out STD_LOGIC; -- Integration Clear Gate
        
        -- Señales de sincronización para adquisición (listas para acoplar al XADC)
        frame_start     : out STD_LOGIC; -- Pulso de inicio de trama
        frame_counter_out : out STD_LOGIC_VECTOR(31 downto 0);
        pixel_valid     : out STD_LOGIC; -- Píxel válido para muestreo
        pixel_count     : out STD_LOGIC_VECTOR(11 downto 0) -- Índice del píxel actual (0 a 3693)
    );
end ccd_clock;

architecture Behavioral of ccd_clock is

    -- Divisor de reloj para phiM
    constant CLK_DIV_COUNT  : integer := CLK_FREQ_HZ / (2 * PHIM_FREQ_HZ);
    
    -- Lectura mínima requerida por datasheet: 3694 píxeles * 4 ciclos phiM/píxel = 14776 ciclos
    constant MIN_READOUT_CYCLES : unsigned(31 downto 0) := to_unsigned(14776, 32);

    -- Señales de reloj
    signal clk_div_cnt  : integer range 0 to CLK_DIV_COUNT - 1 := 0;
    signal phiM_reg     : std_logic := '0';
    signal phiM_tick    : std_logic := '0';

    -- Estados de la máquina FSM
    type state_type is (ST_RESET, ST_ICG_LOW, ST_SH_HIGH, ST_SH_LOW, ST_READOUT, ST_WAIT_INTEGRATION);
    signal state : state_type := ST_RESET;

    -- Contadores
    signal phim_cycle_cnt : unsigned(31 downto 0) := (others => '0');
    signal frame_cnt      : unsigned(31 downto 0) := (others => '0');
    signal total_frames : unsigned(31 downto 0) := (others => '0');
    signal pixel_cnt      : unsigned(11 downto 0) := (others => '0');
    signal phiM_per_pixel : unsigned(1 downto 0)  := (others => '0');
    
    -- Duración de pulsos en ciclos de phiM (a 2 MHz, 1 ciclo = 500 ns)
    -- t2 (ICG low a SH high) = 1 ciclo (500 ns)  [Req: 100ns a 1000ns]
    -- t3 (Ancho de pulso SH)  = 3 ciclos (1.5 us) [Req: > 1000ns]
    -- t1 (ICG low tras SH)   = 3 ciclos (1.5 us) [Req: 1000ns a 5000ns]
    constant T2_CYCLES : unsigned(31 downto 0) := to_unsigned(1, 32);
    constant T3_CYCLES : unsigned(31 downto 0) := to_unsigned(3, 32);
    constant T1_CYCLES : unsigned(31 downto 0) := to_unsigned(3, 32);

    -- Registros internos
    signal sh_reg          : std_logic := '0';
    signal icg_reg         : std_logic := '1';
    signal frame_start_reg : std_logic := '0';
    signal pixel_valid_reg : std_logic := '0';

    signal target_t_int    : unsigned(31 downto 0);

begin

    -- Selección del tiempo de integración (protege contra valores menores al límite físico del CCD)
    process(i_t_int_cycles)
        variable user_t_int : unsigned(31 downto 0);
    begin
        user_t_int := unsigned(i_t_int_cycles);
        if user_t_int < MIN_READOUT_CYCLES then
            if user_t_int = 0 then
                target_t_int <= to_unsigned(DEFAULT_T_INT, 32);
            else
                target_t_int <= MIN_READOUT_CYCLES;
            end if;
        else
            target_t_int <= user_t_int;
        end if;
    end process;

    -- 1. Generador de reloj phiM y pulso tick de sincronización
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            clk_div_cnt <= 0;
            phiM_reg    <= '0';
            phiM_tick   <= '0';
        elsif rising_edge(clk) then
            phiM_tick <= '0';
            if clk_div_cnt = CLK_DIV_COUNT - 1 then
                clk_div_cnt <= 0;
                phiM_reg    <= not phiM_reg;
                if phiM_reg = '0' then
                    phiM_tick <= '1'; -- Pulso de un ciclo de 'clk' en el flanco de subida de phiM
                end if;
            else
                clk_div_cnt <= clk_div_cnt + 1;
            end if;
        end if;
    end process;

    -- 2. Máquina de estados principal del TCD1304
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            state           <= ST_RESET;
            sh_reg          <= '0';
            icg_reg         <= '1';
            phim_cycle_cnt  <= (others => '0');
            frame_cnt       <= (others => '0');
            pixel_cnt       <= (others => '0');
            phiM_per_pixel  <= (others => '0');
            frame_start_reg <= '0';
            pixel_valid_reg <= '0';
        elsif rising_edge(clk) then
            frame_start_reg <= '0';

            if phiM_tick = '1' then
                phim_cycle_cnt <= phim_cycle_cnt + 1;
                frame_cnt      <= frame_cnt + 1;

                case state is

                    when ST_RESET =>
                        sh_reg          <= '0';
                        icg_reg         <= '1';
                        phim_cycle_cnt  <= (others => '0');
                        frame_cnt       <= (others => '0');
                        pixel_cnt       <= (others => '0');
                        state           <= ST_ICG_LOW;

                    -- Flanco descendente de ICG (Inicio de ciclo de obturador)
                    when ST_ICG_LOW =>
                        icg_reg         <= '0';
                        sh_reg          <= '0';
                        frame_start_reg <= '1';
                        if phim_cycle_cnt >= T2_CYCLES - 1 then
                            phim_cycle_cnt <= (others => '0');
                            state          <= ST_SH_HIGH;
                        end if;
                        if phim_cycle_cnt = 0 then
                            total_frames <= total_frames + 1;
                        end if;

                    -- Pulso SH en ALTO
                    when ST_SH_HIGH =>
                        sh_reg <= '1';
                        if phim_cycle_cnt >= T3_CYCLES - 1 then
                            phim_cycle_cnt <= (others => '0');
                            state          <= ST_SH_LOW;
                        end if;

                    -- SH vuelve a BAJO y mantiene ICG en BAJO por el tiempo t1
                    when ST_SH_LOW =>
                        sh_reg <= '0';
                        if phim_cycle_cnt >= T1_CYCLES - 1 then
                            phim_cycle_cnt <= (others => '0');
                            icg_reg        <= '1'; -- Sube ICG: Inicia lectura de píxeles en OS
                            pixel_cnt      <= (others => '0');
                            phiM_per_pixel <= (others => '0');
                            state          <= ST_READOUT;
                        end if;

                    -- Lectura de los 3694 píxeles (4 ciclos de phiM por píxel)
                    when ST_READOUT =>
                        phiM_per_pixel <= phiM_per_pixel + 1;

                        -- Activa la señal de píxel válido en el momento óptimo del periodo
                        if phiM_per_pixel = "01" then
                            pixel_valid_reg <= '1';
                        else
                            pixel_valid_reg <= '0';
                        end if;

                        if phiM_per_pixel = "11" then
                            if pixel_cnt = 3693 then
                                pixel_valid_reg <= '0';
                                state           <= ST_WAIT_INTEGRATION;
                            else
                                pixel_cnt <= pixel_cnt + 1;
                            end if;
                        end if;

                    -- Estado de integración: Espera hasta completar el tiempo t_INT configurado
                    when ST_WAIT_INTEGRATION =>
                        pixel_valid_reg <= '0';
                        if frame_cnt >= target_t_int then
                            phim_cycle_cnt <= (others => '0');
                            frame_cnt      <= (others => '0');
                            state          <= ST_ICG_LOW; -- Inicia la siguiente trama
                        end if;

                    when others =>
                        state <= ST_RESET;

                end case;
            end if;
        end if;
    end process;

    -- Asignación de salidas
    fim         <= phiM_reg;
    clk_o       <= phiM_reg;
    sh          <= sh_reg;
    icg         <= icg_reg;
    
    frame_start <= frame_start_reg;
    pixel_valid <= pixel_valid_reg;
    frame_counter_out <= std_logic_vector(total_frames);
    pixel_count <= std_logic_vector(pixel_cnt);

end Behavioral;