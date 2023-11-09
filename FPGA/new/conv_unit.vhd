library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

entity conv_unit is
    Generic (
        DWIDTH : integer := 32;
        KERNEL_SIZE : integer := 9
    );
    Port (
        -- Image input
        image_block : in signed(DWIDTH*KERNEL_SIZE-1 downto 0);
        kernel : in signed(DWIDTH*KERNEL_SIZE-1 downto 0);
        -- Conv output
        dout : out signed(2*DWIDTH-1 downto 0)
     );
end conv_unit;

architecture Behavioral of conv_unit is
    
    type t_mult_out is array(KERNEL_SIZE-1 downto 0) of signed(2*DWIDTH-1 downto 0);
    signal mult_out : t_mult_out; -- Multiplication stage output
    type t_add_out_1 is array(3 downto 0) of signed(2*DWIDTH-1 downto 0);
    signal add_out_1 : t_add_out_1; -- Addition first stage output
    type t_add_out_2 is array(1 downto 0) of signed(2*DWIDTH-1 downto 0);
    signal add_out_2 : t_add_out_2; -- Addition second stage output
   
begin

-- Combinational logic
-- Multiplies image block with kernel
mult_stage: process(image_block, kernel)
begin
    for k in 0 to KERNEL_SIZE-1 loop
        mult_out(k) <= image_block(DWIDTH*k+DWIDTH-1 downto DWIDTH*k) * kernel(DWIDTH*k+DWIDTH-1 downto DWIDTH*k);
    end loop;
end process mult_stage; 

-- Adds mult(0) + mult(1), mult(2) + mult(3) etc...
-- mult(KERNEL_SIZE-1) left-over
add_stage_1: process(mult_out)
begin
    for k in 0 to 3 loop
       add_out_1(k) <= mult_out(k*2) + mult_out(k*2+1);  
    end loop;
end process add_stage_1; 

-- Adds the first add stage outputs
add_stage_2: process(add_out_1)
begin
    for k in 0 to 1 loop
       add_out_2(k) <= add_out_1(k*2) + add_out_1(k*2+1);  
    end loop;
end process add_stage_2; 

dout <= add_out_2(0) + add_out_2(1) + mult_out(KERNEL_SIZE-1);

end Behavioral;
