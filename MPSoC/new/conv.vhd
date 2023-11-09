library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

entity conv is
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
end conv;

architecture Behavioral of conv is

signal ele_1,ele_2,ele_3,ele_4 : signed(D_WIDTH-1 downto 0);

type state_t is (chunk_wait,row_exe,col_exe);
signal state : state_t; 

type ram_row_t is array(0 to 1, 0 to 3) of signed(D_WIDTH-1 downto 0);
signal ram_row : ram_row_t;

signal row_ctr : integer;

type kernel_t is array(0 to 2, 0 to 2) of signed(D_WIDTH-1 downto 0);
signal kernel : kernel_t;
 
signal alu1_out : signed(2*D_WIDTH-1 downto 0);
signal alu2_out : signed(2*D_WIDTH-1 downto 0);

begin

ele_1 <= image_chunk(31 downto 0);
ele_2 <= image_chunk(63 downto 32);
ele_3 <= image_chunk(95 downto 64);
ele_4 <= image_chunk(127 downto 96);

seq: process(clk,rstn)
    
begin

    if(rstn = '0')
    then
        row_ctr <= 0;
        for i in 0 to 2 loop
            for j in 0 to 2 loop
                kernel(i,j) <= to_signed(1+i+j,D_WIDTH);
        end loop; end loop; 
        for i in 0 to 1 loop
            for j in 0 to 3 loop
                ram_row(i,j) <= (others => '0');
        end loop; end loop; 
        IP_out_valid <= '0';
        out1 <= (others => '0');
        out2 <= (others => '0');
    elsif(rising_edge(clk))
    then
        if(new_chunk = '1')
        then
            ram_row(0,0) <= ele_1; ram_row(0,1) <= ele_2; ram_row(0,2) <= ele_3; ram_row(0,3) <= ele_4;
            ram_row(1,0) <= ram_row(0,0); ram_row(1,1) <= ram_row(0,1); ram_row(1,2) <= ram_row(0,2); ram_row(1,3) <= ram_row(0,3); 
            row_ctr <= row_ctr + 1; 
        end if; 
        
        IP_out_valid <= '0';
        if (row_ctr >= 2 and new_chunk = '1') 
        then
            out1 <= alu1_out;
            out2 <= alu2_out;
            IP_out_valid <= '1';
        end if;
        
    end if; 

end process;


alu1_out <= ram_row(1,0)*kernel(0,0) + ram_row(1,1)*kernel(0,1) + ram_row(1,2)*kernel(0,2)
            + ram_row(0,0)*kernel(1,0) + ram_row(0,1)*kernel(1,1) + ram_row(0,2)*kernel(1,2)
            + ele_1*kernel(0,2) + ele_2*kernel(1,2) + ele_3*kernel(2,2);
            
alu2_out <= ram_row(1,1)*kernel(0,0) + ram_row(1,2)*kernel(0,1) + ram_row(1,3)*kernel(0,2)
            + ram_row(0,1)*kernel(1,0) + ram_row(0,2)*kernel(1,1) + ram_row(0,3)*kernel(1,2)
            + ele_2*kernel(0,2) + ele_3*kernel(1,2) + ele_4*kernel(2,2);



end Behavioral;
