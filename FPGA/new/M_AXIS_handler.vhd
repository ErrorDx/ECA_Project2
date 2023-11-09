library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

entity M_AXIS_handler is
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
end M_AXIS_handler;

architecture bhv of M_AXIS_handler is

type ram_type is array (0 to (IMAGE_LENGTH-2)*(IMAGE_LENGTH-2)-1) of signed(2*DWIDTH-1 downto 0);
signal ram : ram_type;

type state_t is (WAIT_FOR_NEW_RESPONSE, TX, TX_FIN);
signal state : state_t := WAIT_FOR_NEW_RESPONSE;

signal out_valid_i : std_logic := '0';

begin

out_valid <= out_valid_i;

PROC_STATE : process(clk)
    variable ram_index : natural; 
    variable tx_pointer : natural;
begin
    if rising_edge(clk) then
        if rstn = '0' then 
            for k in 0 to (IMAGE_LENGTH-2)*(IMAGE_LENGTH-2)-1 loop
                ram(k) <= (others=>'0');
            end loop;
            out_data <= (others=>'0');
            ram_index := 0;
            tx_pointer := 0;
            out_valid_i <= '0';
            out_last <= '0';
            state <= WAIT_FOR_NEW_RESPONSE;
        else 
            case state is
                when WAIT_FOR_NEW_RESPONSE =>
                    state <= WAIT_FOR_NEW_RESPONSE;
                    for k in 0 to CU_NUMBER-1 loop
                        if (CU_out_valid(k) = '1')
                        then
                            ram(ram_index) <= CU_out_data(2*DWIDTH-1 + k*2*DWIDTH downto 0 + k*2*DWIDTH);
                            ram_index := ram_index + 1; 
                        end if;
                    end loop;
                    if (ram_index = (IMAGE_LENGTH-2)*(IMAGE_LENGTH-2))
                    then 
                        out_data <= std_logic_vector(ram(tx_pointer));
                        out_valid_i <= '1';
                        state <= TX;
                    end if;   
                when TX =>
                    if (out_ready = '1' and out_valid_i = '1') then
                        tx_pointer := tx_pointer + 1;
                        if (tx_pointer = (IMAGE_LENGTH-2)*(IMAGE_LENGTH-2)-1)
                        then
                            out_last <= '1';
                        elsif(tx_pointer = (IMAGE_LENGTH-2)*(IMAGE_LENGTH-2))
                        then 
                            out_last <= '0';
                            out_valid_i <= '0';
                            state <= TX_FIN;
                        end if; 
                    end if;
                when TX_FIN =>
                    --
            end case; 
        end if;
    end if;       
end process;


 
end bhv;