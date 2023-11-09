library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity top_conv is
	generic (
		-- Users to add parameters here
        BRAM_CLK_DELAY: natural := 2;
        BRAM_ADDR_WIDTH : natural := 4;
	    BRAM_DATA_WIDTH : natural := 288;
	    BRAM_BLOCK_WIDTH : natural := 3;
	    IMAGE_LENGTH : natural := 9;
	    DWIDTH : natural := 32
		
	);
	port (
		-- Users to add ports here
	    BRAM_din_a : out std_logic_vector(BRAM_DATA_WIDTH-1 downto 0);
	    BRAM_dout_a : in std_logic_vector(BRAM_DATA_WIDTH-1 downto 0);
	    BRAM_addr_a : out std_logic_vector(BRAM_ADDR_WIDTH-1 downto 0);
        BRAM_we_a : out std_logic;
        clk : in std_logic;
        reset : in std_logic;
        
        -- AXI output interface
        out_last : out std_logic; 
        out_ready : in std_logic;
        out_valid : out std_logic;
        out_data : out std_logic_vector(2*DWIDTH-1 downto 0)

	);
end top_conv;

architecture arch_imp of top_conv is

constant BRAM_BLOCK_DEPTH : natural := 3;
constant CU_NUMBER : natural := BRAM_BLOCK_WIDTH*BRAM_BLOCK_DEPTH;

signal CU_out_valid : std_logic_vector(CU_NUMBER-1 downto 0);
signal CU_out_data : signed(CU_NUMBER*2*DWIDTH-1 downto 0);

component M_AXIS_handler is
    Generic ( 
        CU_NUMBER : natural;
        DWIDTH : natural;
        IMAGE_LENGTH : natural 
    );
    Port ( 
        clk : in std_logic;
        rstn : in std_logic;
 
        -- AXI output interface
        out_last : out std_logic; 
        out_ready : in std_logic;
        out_valid : out std_logic;
        out_data : out std_logic_vector(2*DWIDTH-1 downto 0);
        
        CU_out_valid : in std_logic_vector(CU_NUMBER-1 downto 0);
        CU_out_data : in signed(CU_NUMBER*2*DWIDTH-1 downto 0));
end component M_AXIS_handler;
	
component conv is
	generic (
	    BRAM_CLK_DELAY : natural;
        BRAM_ADDR_WIDTH : natural;
	    BRAM_DATA_WIDTH : natural;
	    BRAM_BLOCK_DEPTH : natural := 3;
	    BRAM_BLOCK_WIDTH : natural; -- The length of the image block brought from BRAM: i.e. BRAM_DATA_WIDTH/BRAM_DATA_DEPTH/DWIDTH i.e the number of 3x1 columns.  
	    CU_NUMBER : natural;    
	        
	    IMAGE_LENGTH: natural; -- depth = width : e.g. 1300 x 1300 
	    KERNEL_LENGTH: natural; -- width = depth : 3 x 3
	    KERNEL_SIZE : natural;
	    DWIDTH : natural
	);
	port (
	   BRAM_din_a : out std_logic_vector(BRAM_DATA_WIDTH-1 downto 0);
	   BRAM_dout_a : in std_logic_vector(BRAM_DATA_WIDTH-1 downto 0);
	   BRAM_addr_a : out std_logic_vector(BRAM_ADDR_WIDTH-1 downto 0);
       BRAM_we_a : out std_logic;
       
       CU_out_buffer : out signed(CU_NUMBER*2*DWIDTH-1 downto 0);
       CU_out_valid_io : out std_logic_vector(CU_NUMBER-1 downto 0);
       
       clk : in std_logic;
       reset : in std_logic
	);
end component conv;

begin

M_AXIS_inst : M_AXIS_handler 
    Generic map ( 
        CU_NUMBER => CU_NUMBER,
        DWIDTH => DWIDTH,
        IMAGE_LENGTH => IMAGE_LENGTH
    )
    Port map ( 
        clk => clk,
        rstn => not reset,
 
        -- AXI output interface
        out_last => out_last, 
        out_ready => out_ready,
        out_valid => out_valid,
        out_data => out_data,
        
        CU_out_valid => CU_out_valid,
        CU_out_data => CU_out_data );

	-- Add user logic here
	
conv_inst : conv 
	generic map (
	    BRAM_CLK_DELAY => BRAM_CLK_DELAY,
        BRAM_ADDR_WIDTH => BRAM_ADDR_WIDTH,
	    BRAM_DATA_WIDTH => BRAM_DATA_WIDTH,
	    BRAM_BLOCK_DEPTH => BRAM_BLOCK_DEPTH,
	    BRAM_BLOCK_WIDTH => BRAM_BLOCK_WIDTH, -- The length of the image block brought from BRAM: i.e. BRAM_DATA_WIDTH/BRAM_DATA_DEPTH/DWIDTH i.e the number of 3x1 columns.  
	        
	    IMAGE_LENGTH => IMAGE_LENGTH, -- depth = width : e.g. 1300 x 1300 
	    KERNEL_LENGTH => 3, -- width = depth : 3 x 3
	    KERNEL_SIZE => 9,
	    DWIDTH => DWIDTH,
	    CU_NUMBER => CU_NUMBER
	)
	port map (
	   BRAM_din_a => BRAM_din_a,
	   BRAM_dout_a => BRAM_dout_a,
	   BRAM_addr_a => BRAM_addr_a,
       BRAM_we_a => BRAM_we_a,
       
       CU_out_buffer => CU_out_data,
       CU_out_valid_io => CU_out_valid,
       
       clk => clk,
       reset => reset
	);

end arch_imp;