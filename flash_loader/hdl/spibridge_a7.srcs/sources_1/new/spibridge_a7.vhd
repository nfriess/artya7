----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 01/31/2019 08:21:48 PM
-- Design Name: 
-- Module Name: spibridge_a7 - Behavioral
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

entity spibridge_a7 is
    Port ( ck_sck : in  STD_LOGIC;
       ck_ss : in  STD_LOGIC;
       ck_mosi : in  STD_LOGIC;
       ck_miso : out  STD_LOGIC;
       qspi_sck : out  STD_LOGIC;
       qspi_cs : out  STD_LOGIC;
       qspi_mosi : out  STD_LOGIC;
       qspi_miso : in  STD_LOGIC;
       qspi_wp : out STD_LOGIC;
       qspi_hold : out STD_LOGIC);
end spibridge_a7;

architecture Behavioral of spibridge_a7 is

begin

	qspi_sck <= ck_sck;
	qspi_cs <= ck_ss;
	qspi_mosi <= ck_mosi;
	ck_miso <= qspi_miso;
	
	qspi_wp <= '1';
	qspi_hold <= '1';
	
end Behavioral;
