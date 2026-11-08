----------------------------------------------------------------------------------
-- Module Name: xadc_sampler_to_RAM - Behavioral
-- Description: Módulo intermedio que activa la conversión en caliente del XADC
--              vía CONVST y envía la dirección (16-bit) y el dato (16-bit) a la
--              memoria RAM del ComBlock.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity xadc_sampler_to_RAM is
    generic (
        DATA_WIDTH  : positive := 16;
        ADDR_WIDTH  : positive := 12 -- 12 bits internos para direccionar 3694 píxeles
    );
    port (
        clk             : in  std_logic; -- Reloj del sistema (100 MHz)
        rst_n           : in  std_logic; -- Reset activo en bajo

        -- Interfaz desde ccd_clock
        sample_trigger  : in  std_logic;                                -- ccd_clock.pixel_valid
        pixel_count_i   : in  std_logic_vector(ADDR_WIDTH-1 downto 0); -- ccd_clock.pixel_count (12 bits)

        -- Interfaz hacia XADC Wizard
        convst_o        : out std_logic;                                -- xadc_wiz.convst_in
        eoc_i           : in  std_logic;                                -- xadc_wiz.eoc_out
        data_xadc_i     : in  std_logic_vector(DATA_WIDTH-1 downto 0); -- xadc_wiz.do_out (16 bits)

        -- Interfaz hacia RAM de ComBlock (Todos en 16 bits)
        ram_clk_o       : out std_logic;                                -- ComBlock.ram_clk_i
        ram_we_o        : out std_logic;                                -- ComBlock.ram_we_i
        ram_addr_o      : out std_logic_vector(15 downto 0);            -- ComBlock.ram_addr_i
        ram_data_o      : out std_logic_vector(15 downto 0)             -- ComBlock.ram_data_i
    );
end entity xadc_sampler_to_RAM;

architecture Behavioral of xadc_sampler_to_RAM is

    signal latched_pixel_addr : std_logic_vector(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal waiting_conversion : std_logic := '0';

begin

    ram_clk_o <= clk;

    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                convst_o           <= '0';
                ram_we_o           <= '0';
                ram_addr_o         <= (others => '0');
                ram_data_o         <= (others => '0');
                latched_pixel_addr <= (others => '0');
                waiting_conversion <= '0';
            else
                -- Pulsos por defecto (duración de 1 ciclo)
                convst_o <= '0';
                ram_we_o <= '0';

                -- 1. Petición de muestreo desde ccd_clock cuando el píxel está listo
                if sample_trigger = '1' and waiting_conversion = '0' then
                    latched_pixel_addr <= pixel_count_i;
                    convst_o           <= '1'; -- Disparo de conversión al XADC
                    waiting_conversion <= '1';
                end if;

                -- 2. El XADC notifica Fin de Conversión (EOC)
                if eoc_i = '1' and waiting_conversion = '1' then
                    ram_addr_o         <= "0000" & latched_pixel_addr; -- Convierte 12 bits a 16 bits (relleno con ceros)
                    ram_data_o         <= data_xadc_i;                  -- Pasa el dato devuelto por el XADC
                    ram_we_o           <= '1';                          -- Habilita escritura en RAM
                    waiting_conversion <= '0';
                end if;
            end if;
        end if;
    end process;

end Behavioral;