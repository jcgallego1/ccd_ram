----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 01/21/2026 06:39:38 AM
-- Design Name: 
-- Module Name: ccd_clock - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity ccd_clock is
    Port ( clk : in STD_LOGIC;
           RST : in STD_LOGIC;
           fim : out STD_LOGIC;
           sh : out STD_LOGIC;
           icg : out STD_LOGIC;
           clk_o : out std_logic
           );
end ccd_clock;

architecture Behavioral of ccd_clock is

signal fim_int  : std_logic := '0';
signal sh_int  : std_logic := '0';
signal icg_int  : std_logic := '0';
signal offset_flag  : std_logic := '1';
signal offset_flag_sh  : std_logic := '1';
signal t1_flag_sh  : std_logic := '0';
signal t2_flag_sh  : std_logic := '0';
signal t3_flag_sh  : std_logic := '0';
signal t4_flag_sh  : std_logic := '0';

signal t1_flag_icg  : std_logic := '0';



signal contador_fim : integer range 0 to 64 := 0;
signal contador_sh : integer range 0 to 5000000 := 0;
signal contador_icg : integer range 0 to 5000000 := 0;

--constants for counts of timers
constant half_cycle_count_fim : integer := 30;
constant t1_num_cycles : integer := 2;  -- usage: (t1_num_cycles * half_cycle_count_fim) - 1 is the limit for this time period, counter starts at 0
constant t2_num_cycles : integer := 25;
constant t3_num_cycles : integer := 25;
constant t4_num_cycles : integer := 8;
constant sum_t : integer := t1_num_cycles + t2_num_cycles + t3_num_cycles + t4_num_cycles;
constant readout_time_cycles : integer := (half_cycle_count_fim * 4 * 2 * 3694) + 28 * half_cycle_count_fim;

begin
--fim module main clock output
process (clk)
begin
   if rising_edge(clk) then
      if contador_fim >= half_cycle_count_fim - 1 then --29 for 2 MHz
         fim_int <=  not fim_int;  
         contador_fim <= 0;
      else
         contador_fim <= contador_fim + 1;
      end if;
   end if;
end process;    

process (clk)
begin
    if rising_edge(clk) then
        if offset_flag_sh = '0' then
            if t1_flag_sh = '0' then  --Flag t1
                if contador_sh >= (half_cycle_count_fim * t1_num_cycles) - 1 then   
                    contador_sh <= 0;
                    sh_int <= not sh_int; --change value for output of sh
                    t1_flag_sh <= '1'; --exit t1
                else
                    contador_sh <= contador_sh + 1;
                end if;
            elsif t1_flag_sh = '1' and t2_flag_sh = '0' then --Flag t2
                if contador_sh >= (half_cycle_count_fim * t2_num_cycles) - 1 then   
                    contador_sh <= 0;
                    sh_int <= not sh_int; --change value for output of sh
                    t2_flag_sh <= '1';
                else
                    contador_sh <= contador_sh + 1;
                end if;
            elsif t2_flag_sh = '1' and t3_flag_sh = '0' then --Flag t3
                if contador_sh >= (half_cycle_count_fim * t3_num_cycles) -1 then   
                    contador_sh <= 0;                    
                    t3_flag_sh <= '1';
                else
                    contador_sh <= contador_sh + 1;
                end if;
            elsif t3_flag_sh = '1' then --Flag t4
                if contador_sh >= (half_cycle_count_fim * t4_num_cycles) - 1 then   
                    contador_sh <= 0;
                    t1_flag_sh <= '0'; --Reset all Flags
                    t2_flag_sh <= '0';
                    t3_flag_sh <= '0';
                else
                    contador_sh <= contador_sh + 1;
                end if;
            end if;    
        else 
            if contador_sh >= half_cycle_count_fim - 1 then
                contador_sh <= 0;
                offset_flag_sh <= '0';
            else 
               contador_sh <= contador_sh + 1;
            end if;    
        end if;
    end if;
end process;    

process (clk)    
begin
   if rising_edge(clk) then
       if offset_flag = '0' then
           if t1_flag_icg = '0' then
                if contador_icg >= (half_cycle_count_fim * sum_t) - 1 then --62 for 2 MHz
                    icg_int <=  not icg_int;  
                    contador_icg <= 0;
                    t1_flag_icg <= '1';
                else
                    contador_icg <= contador_icg + 1;
                end if;
           else          
               if contador_icg >= readout_time_cycles - 1 then --readout time out for icg
                   icg_int <=  not icg_int;
                   contador_icg <= 0;
                   t1_flag_icg <= '0';
               else 
                   contador_icg <= contador_icg + 1;
               end if;               
           end if;
       else
           if contador_icg >= (half_cycle_count_fim * (sum_t + 1)) - 1 then --to offset signal
               contador_icg <= 0;
               offset_flag <= '0';
           else 
               contador_icg <= contador_icg + 1;
           end if;           
       end if;         
   end if;
end process;  

--conexiones para actualizar outputs cuando se actualizan los valores en los procesos
fim <= fim_int;
clk_o <= fim_int;
sh <= sh_int;
icg <= icg_int;


end Behavioral;
