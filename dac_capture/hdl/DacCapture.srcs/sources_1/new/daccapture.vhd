----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 12/01/2018 04:08:39 PM
-- Design Name: 
-- Module Name: daccapture - Behavioral
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
use IEEE.NUMERIC_STD.ALL;

use IEEE.STD_LOGIC_UNSIGNED.all;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;


entity daccapture is
    Port ( CLK100MHZ : in STD_LOGIC;
           btn0 : in STD_LOGIC;
           dac_data : in STD_LOGIC;
           dac_wordclk : in STD_LOGIC;
           dac_bitclk : in STD_LOGIC;
           spi_clk : in STD_LOGIC;
           spi_ce : in STD_LOGIC;
           spi_miso : out STD_LOGIC;
           spi_mosi : in STD_LOGIC;
           --ck_io0 : in STD_LOGIC;
           ck_io26 : out STD_LOGIC;
           sw0 : in STD_LOGIC;
           ja : out STD_LOGIC_VECTOR(7 downto 0);
           jb : out STD_LOGIC_VECTOR(7 downto 0);
           jc : out STD_LOGIC_VECTOR(5 downto 0)
    );
end daccapture;

architecture Behavioral of daccapture is

    constant RAM_WIDTH : integer := 17;
    constant RAM_SIZE : integer := 2**RAM_WIDTH;
    constant RAM_SIZE_HALF : integer := 2**(RAM_WIDTH-1);
    
    signal dac_register : std_logic_vector(19 downto 0);
    signal dac_wordclk_inv : std_logic;
    signal dac_wordclk_sync : std_logic;
    signal dac_wordclk_rdy : std_logic;
    signal dac_wordclk_clr : std_logic;
    signal dac_wordclk_rst : std_logic;
    --signal dac_counter : integer range 0 to RAM_SIZE-1 := 0;
    signal dac_counter : std_logic_vector(RAM_WIDTH-1 downto 0);
    
    signal internal_register : std_logic_vector(19 downto 0);
    signal wordclk_rdy_i : std_logic;
    signal wordclk_rdy_o : std_logic;
    signal wordclk_rdy_clr : std_logic;
    
    signal dac_data_manch_decoded : std_logic;
    signal dac_wordclk_manch_decoded : std_logic;
    
    signal dac_data_internal : std_logic;
    signal dac_wordclk_internal : std_logic;
    
    signal wbm_spi_address : std_logic_vector(23 downto 0);
    signal wbm_spi_readdata : std_logic_vector(15 downto 0);
    signal wbm_spi_writedata : std_logic_vector(15 downto 0);
    signal wbm_spi_strobe : std_logic;
    signal wbm_spi_write : std_logic;
    signal wbm_spi_ack : std_logic := '0';
    signal wbm_spi_cycle : std_logic;
    
    signal sram_din : std_logic_vector(23 downto 0);
    signal sram_dout : std_logic_vector(23 downto 0);
    signal sram_wr_en : std_logic;
    signal sram_rd_en : std_logic;
    signal sram_rd_addr : std_logic_vector(RAM_WIDTH-1 downto 0);
    signal sram_wr_addr : std_logic_vector(RAM_WIDTH-1 downto 0);
    signal sram_rd_addr_low : std_logic;
    
    signal buffer_full_low_i : std_logic;
    signal buffer_full_high_i : std_logic;
    signal buffer_full_low_clr : std_logic;
    signal buffer_full_high_clr : std_logic;
    
    signal need_capture : std_logic := '0';
    
    signal cfg_enable_capture : std_logic := '0';
    signal reg_buffer_full_low : std_logic;
    signal reg_buffer_full_high : std_logic;

begin


process(dac_bitclk) begin

    if rising_edge(dac_bitclk) then
        dac_data_manch_decoded <= dac_data xnor dac_bitclk;
        dac_wordclk_manch_decoded <= dac_wordclk xnor dac_bitclk;
    end if;

end process;


dac_data_internal <= dac_data when sw0 = '0' else dac_data_manch_decoded;
dac_wordclk_internal <= dac_wordclk when sw0 = '0' else dac_wordclk_manch_decoded;
dac_wordclk_inv <= not dac_wordclk_internal;


wordclk_debounce : entity work.debounce
	generic map (
		DELAY => 10
	)
	port map (
		sys_clk => CLK100MHZ,
		sys_reset => '0',
		sig_in => dac_wordclk_inv,
		sig_out => dac_wordclk_sync
	);
	
wordclk_interrupt : entity work.interrupt_reg
    port map ( sys_clk => CLK100MHZ,
           sys_reset => dac_wordclk_rst,
           int_i => dac_wordclk_sync,
           --int_i => dac_wordclk_inv,
           int_o => dac_wordclk_rdy,
           rst_i => dac_wordclk_clr
    );
 
 --wordclk_interrupt : entity work.interrupt_reg
 --    port map ( sys_clk => CLK100MHZ,
 --           sys_reset => dac_wordclk_rst,
 --           int_i => wordclk_rdy_i,
 --           int_o => wordclk_rdy_o,
 --           rst_i => wordclk_rdy_clr
 --    );
    
buffer_full_low_interrupt : entity work.interrupt_reg
    port map ( sys_clk => CLK100MHZ,
           sys_reset => '0',
           int_i => buffer_full_low_i,
           int_o => reg_buffer_full_low,
           rst_i => buffer_full_low_clr
    );

buffer_full_high_interrupt : entity work.interrupt_reg
        port map ( sys_clk => CLK100MHZ,
               sys_reset => '0',
               int_i => buffer_full_high_i,
               int_o => reg_buffer_full_high,
               rst_i => buffer_full_high_clr
        );
	
spi_interface : entity work.spi_wishbone_wrapper
    port map(
        -- Global Signals
        gls_reset => btn0,
        gls_clk   => CLK100MHZ,
        
        -- SPI signals
        mosi => spi_mosi,
        miso => spi_miso,
        sck => spi_clk,
        ss => spi_ce,
        
          -- Wishbone interface signals
        wbm_address    => wbm_spi_address,  	-- Address bus
        wbm_readdata   => wbm_spi_readdata,  	-- Data bus for read access
        wbm_writedata 	=> wbm_spi_writedata,  -- Data bus for write access
        wbm_strobe     => wbm_spi_strobe,                      -- Data Strobe
        wbm_write      => wbm_spi_write,                      -- Write access
        wbm_ack        => wbm_spi_ack,                      -- acknowledge
        wbm_cycle      => wbm_spi_cycle                       -- bus cycle in progress
        );

sram_inst : entity work.dpram
	generic map (
        DATA_WIDTH => 24,
        RAM_WIDTH => RAM_WIDTH
    )
	port map (
		clk => CLK100MHZ,
		rst => btn0,
		din => sram_din,
		wr_en => sram_wr_en,
		rd_en => sram_rd_en,
		wr_addr => sram_wr_addr,
		rd_addr => sram_rd_addr,
		dout => sram_dout
	);


--sram_wr_addr <= std_logic_vector(to_unsigned(dac_counter, sram_wr_addr'length));
sram_wr_addr <= dac_counter;

ck_io26 <= reg_buffer_full_low or reg_buffer_full_high;

ja <= sram_rd_addr(7 downto 0);
jb <= internal_register(15 downto 8);

jc(5) <= buffer_full_high_clr;
jc(4) <= buffer_full_low_clr;
jc(3) <= reg_buffer_full_high;
jc(2) <= sram_rd_en;
jc(1) <= dac_wordclk_rdy;
jc(0) <= dac_wordclk_internal;

process(dac_bitclk) begin

    if rising_edge(dac_bitclk) then
    
        dac_register <= dac_register(18 downto 0) & dac_data_internal;
    
    end if;

end process;


process(dac_wordclk_internal) begin

    if falling_edge(dac_wordclk_internal) then
    
        internal_register <= dac_register;
        --wordclk_rdy_i <= '1';
    
    end if;
    --if rising_edge(dac_wordclk_internal) then
    --    wordclk_rdy_i <= '0';
    --end if;

end process;




sram_din <= internal_register(19) & internal_register(19) & internal_register(19) & internal_register(19) & internal_register;

process(CLK100MHZ) begin
    if rising_edge(CLK100MHZ) then
        
        sram_wr_en <= '0';
        --wordclk_rdy_clr <= '0';
        dac_wordclk_rst <= '0';
        dac_wordclk_clr <= '0';
        buffer_full_low_i <= '0';
        buffer_full_high_i <= '0';

        if cfg_enable_capture = '1' then
        
            --if wordclk_rdy_o = '1' then
            if dac_wordclk_rdy = '1' then
                
                sram_wr_en <= '1';
                
                --wordclk_rdy_clr <= '1';
                dac_wordclk_clr <= '1';
                
                dac_counter <= dac_counter + 1;
                --if dac_counter = (RAM_SIZE - 1) then
                if dac_counter = "11111111111111111" then
                    --dac_counter <= 0;
                    dac_counter <= (others => '0');
                end if;
                
                --if dac_counter = (RAM_SIZE_HALF - 1) then
                if dac_counter = "01111111111111111" then
                    buffer_full_low_i <= '1';
                end if;
                
                --if dac_counter = (RAM_SIZE - 1) then
                if dac_counter = "11111111111111111" then
                    buffer_full_high_i <= '1';
                end if;
                
             end if;
             
        else
            
            --dac_counter <= 0;
            dac_counter <= (others => '0');
            dac_wordclk_rst <= '1';
        
        end if;
        
    end if;
end process;


process(CLK100MHZ) begin
    if rising_edge(CLK100MHZ) then
    
        sram_rd_en <= '0';
        need_capture <= '0';
        
        buffer_full_low_clr <= '0';
        buffer_full_high_clr <= '0';
    
        if wbm_spi_strobe = '1' and wbm_spi_cycle = '1' then
        
            if wbm_spi_write = '1' then
            
                if wbm_spi_address(18 downto 0) = "100" & x"0000" then
                    cfg_enable_capture <= wbm_spi_writedata(0);
                    wbm_spi_ack <= '1';
                elsif wbm_spi_address(18 downto 0) = "100" & x"0003" then
                    buffer_full_low_clr <= wbm_spi_writedata(0);
                    buffer_full_high_clr <= wbm_spi_writedata(1);
                    wbm_spi_ack <= '1';
                end if;
                
            else
            
                if wbm_spi_address(18 downto 0) = "100" & x"0000" then
                    wbm_spi_readdata <= x"000" & "000" & cfg_enable_capture;
                    wbm_spi_ack <= '1';
                elsif wbm_spi_address(18 downto 0) = "100" & x"0001" then
                    wbm_spi_readdata <= sram_wr_addr(15 downto 0);
                    wbm_spi_ack <= '1';
                elsif wbm_spi_address(18 downto 0) = "100" & x"0002" then
                    wbm_spi_readdata <= x"000" & "000" & sram_wr_addr(16);
                    wbm_spi_ack <= '1';
                elsif wbm_spi_address(18 downto 0) = "100" & x"0003" then
                    wbm_spi_readdata <= x"000" & "00" & reg_buffer_full_high & reg_buffer_full_low;
                    wbm_spi_ack <= '1';
                    
                elsif wbm_spi_address(18) = '0' and wbm_spi_ack = '0' then
                    sram_rd_addr <= wbm_spi_address(RAM_WIDTH downto 1);
                    sram_rd_addr_low <= wbm_spi_address(0);
                    sram_rd_en <= '1';
                    need_capture <= '1';
                end if;

            end if;
        
        else
            wbm_spi_ack <= '0';
        end if;
        
        if need_capture = '1' then
            if sram_rd_addr_low = '1' then
                wbm_spi_readdata <= x"00" & sram_dout(23 downto 16);
            else
                wbm_spi_readdata <= sram_dout(15 downto 0);
            end if;
            wbm_spi_ack <= '1';
        end if;
    
    end if;
end process;


end Behavioral;
