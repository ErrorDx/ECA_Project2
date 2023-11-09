library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity top is
    Generic (  
        AXIS_DATA_WIDTH : natural := 128;
        D_WIDTH : natural := 32
    );
    Port ( 
        clk : in std_logic;
        rstn : in std_logic;
 
        -- AXI input interface
        in_ready : out std_logic;
        in_valid : in std_logic;
        in_data : in std_logic_vector(AXIS_DATA_WIDTH-1 downto 0);
        in_last : in std_logic; 
        
        -- AXI output interface 
        out_last : out std_logic; 
        out_ready : in std_logic;
        out_valid : out std_logic;
        out_data : out std_logic_vector(AXIS_DATA_WIDTH-1 downto 0)
        );
            
end top;

architecture bhv of top is

signal image_chunk : signed(AXIS_DATA_WIDTH-1 downto 0); -- 4 32-bit element row 
signal new_chunk : std_logic;
signal out1 : signed(2*D_WIDTH-1 downto 0);
signal out2 : signed(2*D_WIDTH-1 downto 0);
signal IP_out_valid : std_logic;

component axis_handle is
    Generic (  
        AXIS_DATA_WIDTH : natural := 128;
        D_WIDTH : natural := 32
    );
    Port ( 
        clk : in std_logic;
        rstn : in std_logic;
 
        -- AXI input interface
        in_ready : out std_logic;
        in_valid : in std_logic;
        in_data : in std_logic_vector(AXIS_DATA_WIDTH-1 downto 0);
        in_last : in std_logic; 
        
        -- AXI output interface 
        out_last : out std_logic; 
        out_ready : in std_logic;
        out_valid : out std_logic;
        out_data : out std_logic_vector(AXIS_DATA_WIDTH-1 downto 0);
        
        -- custom IP interface
        image_chunk : out signed(AXIS_DATA_WIDTH-1 downto 0); -- 4 32-bit element row 
        new_chunk : out std_logic;
        out1 : in signed(2*D_WIDTH-1 downto 0);
        out2 : in signed(2*D_WIDTH-1 downto 0);
        IP_out_valid : in std_logic);
               
end component;

component conv is
    Generic (
        BUS_WIDTH : natural := 128;
        D_WIDTH : natural := 32 
    );
    Port ( 
        clk : in std_logic;
        rstn : in std_logic; 
        image_chunk : in signed(BUS_WIDTH-1 downto 0); -- 4 32-bit element row 
        new_chunk : in std_logic;
        out1 : out signed(2*D_WIDTH-1 downto 0);
        out2 : out signed(2*D_WIDTH-1 downto 0);
        IP_out_valid : out std_logic
    );
end component;

begin

conv_inst : conv 
 generic map (
    BUS_WIDTH => AXIS_DATA_WIDTH,
    D_WIDTH => D_WIDTH
 )
 port map (
    clk => clk,
    rstn => rstn,
    image_chunk => image_chunk,
    new_chunk => new_chunk,
    out1 => out1,
    out2 => out2,
    IP_out_valid => IP_out_valid);
    
    
axis_inst : axis_handle
 generic map (
    AXIS_DATA_WIDTH => AXIS_DATA_WIDTH,
    D_WIDTH => D_WIDTH
 )
 port map (
    clk => clk,
    rstn => rstn,
    in_ready => in_ready,
    in_valid => in_valid,
    in_data => in_data,
    in_last => in_last,
    out_last => out_last,
    out_ready => out_ready,
    out_valid => out_valid,
    out_data => out_data,  
    image_chunk => image_chunk,
    new_chunk => new_chunk,
    out1 => out1,
    out2 => out2,
    IP_out_valid => IP_out_valid
 );    
end bhv;
