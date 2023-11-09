library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity axis_interface is
    Generic (  
        FIFO_DEPTH : natural := 4;
        AXIS_DATA_WIDTH : natural := 64
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
        out_data : out std_logic_vector(AXIS_DATA_WIDTH-1 downto 0));
end axis_interface;

architecture bhv of axis_interface is

-- The FIFO is full when the RAM contains ram_depth - 1 elements
type ram_type is array (0 to FIFO_DEPTH - 1) of std_logic_vector(in_data'range);
signal ram : ram_type;

-- Input handler
signal in_ready_i : std_logic;
signal start_ctr : std_logic; 
signal ctr : signed(AXIS_DATA_WIDTH-1 downto 0);

-- Output handler 
signal out_data_i : signed(AXIS_DATA_WIDTH-1 downto 0);

begin

-- AXIS Input
in_ready <= in_ready_i;

RX_seq : process(rstn,clk)
begin
        if rstn = '0' then 
            in_ready_i <= '0';
            start_ctr <= '0';
            ctr <= (others => '0');
        elsif rising_edge(clk) then 
            in_ready_i <= '1';
            
            if (in_ready_i = '1' and in_valid = '1' and in_last = '1')
            then
                start_ctr <= '0';
            elsif (in_ready_i = '1' and in_valid = '1')
            then
                start_ctr <= '1';
            end if;
            
            if (start_ctr = '1')
            then
                ctr <= ctr + 1;
            end if;
        end if;     
end process;

-- AXIS Output 
out_data <= std_logic_vector(out_data_i);

TX_seq : process(rstn, clk)
begin
        if rstn = '0' then 
            out_data_i <= (others => '0');
            out_last <= '0';
            out_valid <= '0';
        elsif rising_edge(clk) then
            out_last <= '1';
            out_valid <= '1';
            out_data_i <= ctr;    
        end if;     
end process;

end architecture;
