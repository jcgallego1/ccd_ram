----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 03/03/2026 05:53:48 AM
-- Design Name: 
-- Module Name: xadc_sampler_to_FIFO - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- This module accepts the xadc converted values once every 4 clock cycles of the CCD_driver
-- Aditionally, it sends those values to a FIFO (ComBlock PL -> PS)
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- CCD
-- roe_in -> read out enable in (Corresponds to a flag: '0' when is time to read the xadc because
-- the CCD is in Read Out Time mode; '1' when the driver and CCD are waiting to enter again the Read Out Time mode)
-- ccd_clk_in -> corresponds to the clock wich drives the CCD
-- XADC
-- data_xadc_in -> data out of the xadc
-- FIFO
-- we_o -> write enable output
-- data_o -> write the data to the FIFO
-- full_i -> IN_FIFO Full flag (connects to comblock to know if the FIFO is FULL)
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity xadc_sampler_to_FIFO is
   generic (
      WIDTH     : positive := 16;
      NUM_SAMPLES : positive := 3600   -- can be made generic too
   );
   port (
      reset       : in  std_logic;
      
      -- CCD / slow clock domain
--      roe_i       : in  std_logic;              -- optional: can be used to enable/disable
      ccd_clk_i   : in  std_logic;              -- 2 MHz example
      
      -- XADC fast domain signals (already synchronized if needed)
      data_xadc_i : in  std_logic_vector(15 downto 0);  -- result
      eoc_i       : in  std_logic;                      -- from XADC
      convst_o    : out std_logic;                      -- to XADC CONVST
      
      -- ComBlock FIFO interface
      we_o        : out std_logic;                      -- write enable
      data_o      : out std_logic_vector(WIDTH-1 downto 0);
      full_i      : in  std_logic                       -- FIFO full flag
   );
end entity;

architecture Behavioral of xadc_sampler_to_FIFO is

   -- Internal signals
   signal eoc_sync       : std_logic_vector(2 downto 0) := (others => '0');
   signal eoc_rising     : std_logic := '0';
   signal convst_pulse   : std_logic := '0';
   signal cycle_cnt      : unsigned(1 downto 0) := (others => '0');
   signal sample_cnt     : unsigned(11 downto 0) := (others => '0');  -- 0 to 3599
   signal done           : std_logic := '0';
   
   -- Control whether we are still collecting
   signal collecting     : std_logic := '1';

begin

   ----------------------------------------------------------------------------
   -- Generate CONVST pulse every 4 CCD clock cycles
   ----------------------------------------------------------------------------
   process (ccd_clk_i)
   begin
      if rising_edge(ccd_clk_i) then
         if reset = '1' or done = '1' or collecting = '0' then
            cycle_cnt     <= (others => '0');
            convst_pulse  <= '0';
         else
            convst_pulse <= '0';               -- default
            cycle_cnt    <= cycle_cnt + 1;

            if cycle_cnt = 3 then
               cycle_cnt     <= (others => '0');
               convst_pulse  <= '1';           -- single-cycle pulse
            end if;
         end if;
      end if;
   end process;

   convst_o <= convst_pulse;

   ----------------------------------------------------------------------------
   -- Synchronize EOC (from fast → slow domain)
   ----------------------------------------------------------------------------
   process (ccd_clk_i)
   begin
      if rising_edge(ccd_clk_i) then
         if reset = '1' then
            eoc_sync <= (others => '0');
         else
            eoc_sync <= eoc_sync(1 downto 0) & eoc_i;
         end if;
      end if;
   end process;

   -- Rising edge detection (clean after synchronization)
   eoc_rising <= '1' when eoc_sync(2) = '0' and eoc_sync(1) = '1' else '0';

   ----------------------------------------------------------------------------
   -- Write to FIFO when new sample is ready (and FIFO not full)
   ----------------------------------------------------------------------------
   process (ccd_clk_i)
   begin
      if rising_edge(ccd_clk_i) then
         if reset = '1' then
            sample_cnt   <= (others => '0');
            done         <= '0';
            collecting   <= '1';
            we_o         <= '0';
            data_o       <= (others => '0');
         else
            we_o     <= '0';                     -- default: no write

            -- Only attempt write if we are still collecting and FIFO has space
            if collecting = '1' and full_i = '0' then
               if eoc_rising = '1' then
                  -- Write the 12-bit sample, pad upper 4 bits with 0
                  data_o   <= data_xadc_i;   -- or "0000" & data_xadc_i(11 downto 0)
                  we_o     <= '1';                    -- write pulse

                  -- Count up
                  if sample_cnt < (NUM_SAMPLES - 1) then
                     sample_cnt <= sample_cnt + 1;
                  else
                     sample_cnt <= (others => '0');
                     done       <= '1';
                     collecting <= '0';           -- stop collecting
                  end if;
               end if;
            end if;
         end if;
      end if;
   end process;

end Behavioral;