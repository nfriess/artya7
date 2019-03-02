----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    10:56:07 02/26/2017 
-- Design Name: 
-- Module Name:    debounce - Behavioral 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
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
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity debounce is
	 generic (DELAY : positive
	 );
    Port ( sys_clk : in  STD_LOGIC;
           sys_reset : in  STD_LOGIC;
           sig_in : in  STD_LOGIC;
           sig_out : out  STD_LOGIC);
end debounce;

architecture Behavioral of debounce is

	signal shift_reg : std_logic_vector(DELAY downto 0);
	
	signal reset_internal : std_logic;

begin

	sig_out <= shift_reg(DELAY);
	
	reset_internal <= '1' when sys_reset = '1' or sig_in = '0' else '0';

	process(sys_clk, reset_internal)
	begin
	
		if reset_internal = '1' then
			
			shift_reg <= (others => '0');
			
		elsif rising_edge(sys_clk) then
		
			shift_reg <= shift_reg(DELAY - 1 downto 0) & sig_in;
		
		end if;
	
	end process;


end Behavioral;

