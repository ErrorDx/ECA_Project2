library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity axis_handle is
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
        
        
end axis_handle;

architecture bhv of axis_handle is

-- Input handler
signal in_ready_i : std_logic;


-- Output handler 
signal out_data_i : signed(AXIS_DATA_WIDTH-1 downto 0);
signal out_valid_i : std_logic;

begin

-- AXIS Input
in_ready <= in_ready_i;

RX_seq : process(rstn,clk)
begin
        if rstn = '0' then 
            in_ready_i <= '0';
            new_chunk <= '0';
            image_chunk <= (others=>'0');
        elsif rising_edge(clk) then 
            in_ready_i <= '1';
            new_chunk <= '0';
            if (in_ready_i = '1' and in_valid = '1')
            then
                image_chunk <= signed(in_data);
                new_chunk <= '1';
            end if; 
        end if;     
end process;

-- AXIS Output 
out_data <= std_logic_vector(out_data_i);
out_valid <= out_valid_i;
TX_seq : process(rstn, clk)
variable ctr : natural;
begin
        if rstn = '0' then 
            out_data_i <= (others => '0');
            out_last <= '0';
            out_valid_i <= '0';
            ctr := 0;
        elsif rising_edge(clk) then
            if (IP_out_valid = '1')
            then 
                out_valid_i <= '1';   
                out_data_i <= out1 & out2;
                ctr := ctr + 1;
                if (ctr > 842401)
                then
                    out_last <= '1';
                end if; 
            end if;
            
            if (out_valid_i = '1' and out_ready = '1')
            then
                out_valid_i <= '0';
            end if;  
        end if;     
end process;

end architecture;
