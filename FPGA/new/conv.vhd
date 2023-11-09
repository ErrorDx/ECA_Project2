library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity conv is
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
end conv;

architecture arch_imp of conv is 

-- Convulution unit (CU)
component conv_unit is
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
end component conv_unit;

-- Wires to and from CUs
type t_CU_image_block is array (0 to CU_NUMBER-1) of signed(DWIDTH*KERNEL_SIZE-1 downto 0); 
type t_CU_dout is array (0 to CU_NUMBER-1) of signed(2*DWIDTH-1 downto 0); 
signal CU_image_block : t_CU_image_block;
signal CU_dout : t_CU_dout;
signal kernel_buffer :signed(DWIDTH*KERNEL_SIZE-1 downto 0); 

-- Internal BRAM receiver signals 
signal BRAM_addr_a_i : unsigned(BRAM_ADDR_WIDTH-1 downto 0); -- (for cleaner type conversions)
signal BRAM_out_buffer : signed(BRAM_DATA_WIDTH-1 downto 0);
signal ctr : natural;
signal column_offset : natural;
signal prev_column_offset : natural; 

-- Total buffer space for the image elements 
constant HORI_IMAGE_BUFFER_SIZE : natural := (KERNEL_LENGTH-1)*BRAM_BLOCK_WIDTH;
constant VERT_IMAGE_BUFFER_SIZE : natural := (KERNEL_LENGTH-1)*BRAM_BLOCK_DEPTH;
constant COR_IMAGE_BUFFER_SIZE : natural := (KERNEL_LENGTH-1)*(KERNEL_LENGTH-1);

type t_HORI_image_buffer is array (0 to IMAGE_LENGTH/BRAM_BLOCK_WIDTH-1) of signed(DWIDTH*HORI_IMAGE_BUFFER_SIZE-1 downto 0); 
signal HORI_image_buffer : t_HORI_image_buffer; -- Register
signal VERT_image_buffer : signed(DWIDTH*VERT_IMAGE_BUFFER_SIZE-1 downto 0); -- Register
signal COR_image_buffer : signed(DWIDTH*COR_IMAGE_BUFFER_SIZE-1 downto 0);
signal HORI_image_buffer_next : t_HORI_image_buffer; -- Wires
signal VERT_image_buffer_next : signed(DWIDTH*VERT_IMAGE_BUFFER_SIZE-1 downto 0); -- Wires
signal COR_image_buffer_next : signed(DWIDTH*COR_IMAGE_BUFFER_SIZE-1 downto 0);

-- Control signals
 -- State declaration
    type cu_control is (init, left_corner, edge, row_transition, sandwich, fin);
    signal current_state, next_state : cu_control;
 -- ctrl inputs
    signal new_image_block : std_logic; 
   
-- Output buffers
signal CU_out_valid : std_logic_vector(CU_NUMBER-1 downto 0);
signal CU_out_valid_next : std_logic_vector(CU_NUMBER-1 downto 0);
signal CU_out_data : signed(CU_NUMBER*2*DWIDTH-1 downto 0);
signal CU_out_data_buffer : signed(CU_NUMBER*2*DWIDTH-1 downto 0);


begin
-- Convolution logic units:
CUs : for i in 0 to CU_NUMBER-1 generate
    CUx: conv_unit
    generic map (
        DWIDTH => DWIDTH,
        KERNEL_SIZE => KERNEL_SIZE
    )
    port map (
        -- Image input
        image_block => CU_image_block(i),
        kernel => kernel_buffer,
        -- Conv output
        dout => CU_dout(i)
    );
end generate CUs;

    -- output logic combi
    CU_out : process(CU_dout)
    begin
        for k in 0 to CU_NUMBER - 1 loop
            CU_out_data(2*DWIDTH-1 + k*2*DWIDTH downto 0 + k*2*DWIDTH) <= CU_dout(k);
        end loop;
    end process CU_out;
    
    CU_out_buffer <= CU_out_data_buffer;
    CU_out_valid_io <= CU_out_valid;

    -- sequential logic
    seq: process(clk,reset) 
    begin
        if reset = '1' 
        then 
            for k in 0 to IMAGE_LENGTH/BRAM_BLOCK_WIDTH-1 loop
                HORI_image_buffer(k) <= (others => '0');
            end loop;           
            VERT_image_buffer <= (others => '0');
            COR_image_buffer <= (others => '0');
            CU_out_valid <= (others => '0');
            CU_out_data_buffer <= (others => '0');
            for k in 0 to KERNEL_SIZE-1 loop
                kernel_buffer(DWIDTH*k+DWIDTH-1 downto DWIDTH*k) <= to_signed(k+1, DWIDTH);
            end loop;
            current_state <= init;
        elsif rising_edge(clk)
        then    
            CU_out_data_buffer <= CU_out_data;
            current_state <= next_state;      
            HORI_image_buffer <= HORI_image_buffer_next;
            VERT_image_buffer <= VERT_image_buffer_next;
            COR_image_buffer <= COR_image_buffer_next;
            CU_out_valid <= CU_out_valid_next;
        end if;
    end process seq;  
    
    
    -- next state transition
    new_state: process(current_state,new_image_block) 
        variable new_block_ctr : natural; 
        variable row_ctr : natural;
    begin
        case current_state is 
            when init =>
            
                if (new_image_block = '1')
                then
                    next_state <= left_corner;
                end if; 
              
            when left_corner =>
                row_ctr := 0;
                
                if (new_image_block = '1')
                then
                    next_state <= edge;
                    new_block_ctr := 0;
                end if;
                
            when edge =>
            
                if (new_image_block = '1')
                then
                    new_block_ctr := new_block_ctr + 1; 
                end if;
                
                if (new_block_ctr = IMAGE_LENGTH/BRAM_BLOCK_WIDTH - 1)
                then
                    next_state <= row_transition;
                    row_ctr := row_ctr + 1;
                    new_block_ctr := 0;
                end if;
                
            when row_transition =>
            
                if (new_image_block = '1')
                then
                    next_state <= sandwich;
                    new_block_ctr := 0;
                end if;
                
            when sandwich =>
            
                if (new_image_block = '1')
                then
                    new_block_ctr := new_block_ctr + 1; 
                end if;
                
                if (new_block_ctr = IMAGE_LENGTH/BRAM_BLOCK_WIDTH - 1)
                then
                    row_ctr := row_ctr + 1;
                    if (row_ctr = IMAGE_LENGTH/BRAM_BLOCK_DEPTH)
                    then 
                        next_state <= fin; 
                    else
                        next_state <= row_transition;
                        new_block_ctr := 0;
                    end if;
                end if;
            when fin => 
                NULL; 
            end case;     
     end process new_state; 

    -- state outputs
    outputs: process(next_state, HORI_image_buffer, VERT_image_buffer, COR_image_buffer, BRAM_out_buffer, column_offset, prev_column_offset) 
        constant ELE_1 : natural := DWIDTH; -- 1 element offset
        constant ELE_3 : natural := DWIDTH*KERNEL_LENGTH; -- 3x1 column offset
        constant ELE_9 : natural := DWIDTH*KERNEL_SIZE; -- 3x3 offset
        constant ELE_2 : natural := DWIDTH*(KERNEL_LENGTH - 1); -- 2x1 element offset
        constant ELE_4 : natural := DWIDTH*4; -- 2x2 element offset
        constant ELE_5 : natural := DWIDTH*5;
        constant ELE_6 : natural := DWIDTH*6; -- 3x2 element offset
        
        variable temp : signed(DWIDTH*HORI_IMAGE_BUFFER_SIZE-1 downto 0); 
        variable temp2 : signed(DWIDTH*HORI_IMAGE_BUFFER_SIZE-1 downto 0); 
        variable temp_index : natural; 
    begin
        case next_state is 
            when init =>
                for k in 0 to CU_NUMBER-1 loop
                    CU_image_block(k) <= (others => '0');
                end loop;
                HORI_image_buffer_next <= HORI_image_buffer;
                VERT_image_buffer_next <= VERT_image_buffer;
                COR_image_buffer_next <= COR_image_buffer;
                CU_out_valid_next <= CU_out_valid;
                temp_index := 0;
            when left_corner =>
                
                -- Compute convolution 
                for k in 0 to BRAM_BLOCK_WIDTH-BRAM_BLOCK_DEPTH loop
                    CU_image_block(k) <= BRAM_out_buffer(ELE_9-1 + k*ELE_3  downto 0 + k*ELE_3);
                end loop;
                for k in BRAM_BLOCK_WIDTH-BRAM_BLOCK_DEPTH+1 to CU_NUMBER-1 loop
                    CU_image_block(k) <= (others => '0');
                end loop;
                -- Store current BRAM output in image_buffer
                HORI_image_buffer_next <= HORI_image_buffer;
                for k in 0 to BRAM_BLOCK_WIDTH-1 loop
                    temp(ELE_2-1 + k*ELE_2 downto 0 + k*ELE_2) := BRAM_out_buffer(ELE_3-1 + k*ELE_3 downto ELE_1 + k*ELE_3);
                end loop;
                HORI_image_buffer_next(0) <= temp;
                --for k in 1 to IMAGE_LENGTH/BRAM_BLOCK_WIDTH - 1 loop
                --   HORI_image_buffer_next(k) <= HORI_image_buffer(k);
                --end loop;             
                VERT_image_buffer_next <= BRAM_out_buffer(BRAM_DATA_WIDTH-1 downto BRAM_DATA_WIDTH - (VERT_IMAGE_BUFFER_SIZE*DWIDTH) );
                COR_image_buffer_next <= COR_image_buffer;
                temp_index := 0;
                
                CU_out_valid_next <= (others => '0');
                if (prev_column_offset /= column_offset)
                then 
                    for k in 0 to BRAM_BLOCK_WIDTH-BRAM_BLOCK_DEPTH loop
                        CU_out_valid_next(k) <= '1';
                    end loop;
                else 
                    CU_out_valid_next <= (others => '0');
                end if;
            when edge =>
                
                -- Compute convolution
                for k in 0 to 1 loop
                    CU_image_block(k) <= BRAM_out_buffer(ELE_3-1 + k*ELE_3 downto 0) & VERT_image_buffer(DWIDTH*VERT_IMAGE_BUFFER_SIZE-1 downto 0 + k*ELE_3);
                end loop;               
                for k in 2 to BRAM_BLOCK_WIDTH-BRAM_BLOCK_DEPTH+2  loop
                    CU_image_block(k) <= BRAM_out_buffer(ELE_9-1 + (k-2)*ELE_3 downto 0 + (k-2)*ELE_3);
                end loop;               
                for k in BRAM_BLOCK_WIDTH-BRAM_BLOCK_DEPTH+2+1 to CU_NUMBER-1 loop
                    CU_image_block(k) <= (others => '0');
                end loop;
                -- Store current BRAM output in image_buffer  
                HORI_image_buffer_next <= HORI_image_buffer;
                for k in 0 to BRAM_BLOCK_WIDTH-1 loop
                    temp(ELE_2-1 + k*ELE_2 downto 0 + k*ELE_2) := BRAM_out_buffer(ELE_3-1 + k*ELE_3 downto ELE_1 + k*ELE_3);
                end loop;
                HORI_image_buffer_next(column_offset-1) <= temp;
                VERT_image_buffer_next <= BRAM_out_buffer(BRAM_DATA_WIDTH-1 downto BRAM_DATA_WIDTH - (VERT_IMAGE_BUFFER_SIZE*DWIDTH) );
                COR_image_buffer_next <= COR_image_buffer;
                temp_index := 0;
                
                CU_out_valid_next <= (others => '0');             
                if (prev_column_offset /= column_offset)
                then 
                    for k in 0 to 1 loop
                        CU_out_valid_next(k) <= '1';
                    end loop;
                    for k in 2 to BRAM_BLOCK_WIDTH-BRAM_BLOCK_DEPTH+2  loop
                        CU_out_valid_next(k) <= '1';
                    end loop; 
                else 
                    CU_out_valid_next <= (others => '0');
                end if;
                
            when row_transition =>
                for k in 0 to CU_NUMBER - 1 loop
                    CU_image_block(k) <= (others=>'0');
                end loop;
                -- Compute convolution
                temp2 := HORI_image_buffer(0);
                for j in 0 to (KERNEL_LENGTH - 1) loop
                    for k in 0 to BRAM_BLOCK_WIDTH-BRAM_BLOCK_DEPTH  loop
                        CU_image_block(temp_index) <=  
                            BRAM_out_buffer(2*ELE_3+ELE_1-1 + k*ELE_3 + j*ELE_1 downto 2*ELE_3 + k*ELE_3)
                            & temp2(ELE_6-1 + k*ELE_2 downto ELE_4 + k*ELE_2 + j*ELE_1)
                            & BRAM_out_buffer(ELE_4-1 + k*ELE_3 + j*ELE_1 downto ELE_3 + k*ELE_3)
                            & temp2(ELE_4-1 + k*ELE_2 downto ELE_2 + k*ELE_2 + j*ELE_1)
                            & BRAM_out_buffer(ELE_1-1 + k*ELE_3 + j*ELE_1 downto 0 + k*ELE_3)
                            & temp2(ELE_2-1 + k*ELE_2 downto 0 + k*ELE_2 + j*ELE_1);
                        temp_index := temp_index + 1;
                    end loop;
                end loop;    
                temp_index := 0;               
                -- Store current BRAM output in image_buffer
                HORI_image_buffer_next <= HORI_image_buffer;
                for k in 0 to BRAM_BLOCK_WIDTH-1 loop
                    temp(ELE_2-1 + k*ELE_2 downto 0 + k*ELE_2) := BRAM_out_buffer(ELE_3-1 + k*ELE_3 downto ELE_1 + k*ELE_3);
                end loop;
                HORI_image_buffer_next(0) <= temp;
                VERT_image_buffer_next <= BRAM_out_buffer(BRAM_DATA_WIDTH-1 downto BRAM_DATA_WIDTH - (VERT_IMAGE_BUFFER_SIZE*DWIDTH) );
                if (prev_column_offset /= column_offset)
                then 
                    COR_image_buffer_next <= temp2(DWIDTH*HORI_IMAGE_BUFFER_SIZE-1 downto DWIDTH*HORI_IMAGE_BUFFER_SIZE - ELE_4);
                else 
                    COR_image_buffer_next <= COR_image_buffer;
                end if;
                
                CU_out_valid_next <= (others => '0');             
                if (prev_column_offset /= column_offset)
                then 
                    for j in 0 to (KERNEL_LENGTH - 1) loop
                        for k in 0 to BRAM_BLOCK_WIDTH-BRAM_BLOCK_DEPTH  loop
                            CU_out_valid_next(temp_index) <= '1';
                            temp_index := temp_index + 1;
                        end loop;
                    end loop;    
                    temp_index := 0; 
                else 
                    CU_out_valid_next <= (others => '0');
                end if;
            when sandwich =>
                -- Compute convolution
                temp2 := HORI_image_buffer(column_offset-1);
                CU_image_block(0) <= 
                    BRAM_out_buffer(ELE_1-1 downto 0) & temp2(ELE_2-1 downto 0)
                    & VERT_image_buffer(ELE_4-1 downto ELE_3) & COR_image_buffer(ELE_4-1 downto ELE_2)
                    & VERT_image_buffer(ELE_1-1 downto 0) & COR_image_buffer(ELE_2-1 downto 0);
                CU_image_block(1) <= 
                    BRAM_out_buffer(ELE_4-1 downto ELE_3) & temp2(ELE_4-1 downto ELE_2)
                    & BRAM_out_buffer(ELE_1-1 downto 0) & temp2(ELE_2-1 downto 0)
                    & VERT_image_buffer(ELE_4-1 downto ELE_3) & COR_image_buffer(ELE_4-1 downto ELE_2);
                CU_image_block(2) <= 
                    BRAM_out_buffer(ELE_2-1 downto 0) & temp2(ELE_2-1 downto ELE_1)
                    & VERT_image_buffer(ELE_5-1 downto ELE_3) & COR_image_buffer(ELE_4-1 downto ELE_3)  
                    & VERT_image_buffer(ELE_2-1 downto 0) & COR_image_buffer(ELE_2-1 downto ELE_1); 
                CU_image_block(3) <= 
                    BRAM_out_buffer(ELE_5-1 downto ELE_3) & temp2(ELE_4-1 downto ELE_3)
                    & BRAM_out_buffer(ELE_2-1 downto 0) & temp2(ELE_2-1 downto ELE_1)  
                    & VERT_image_buffer(ELE_5-1 downto ELE_3) & COR_image_buffer(ELE_4-1 downto ELE_3);  
                    -- edge-like                       
                temp_index := 4;
                for k in 0 to 1 loop
                    CU_image_block(temp_index) <= BRAM_out_buffer(ELE_3-1 + k*ELE_3 downto 0) & VERT_image_buffer(DWIDTH*VERT_IMAGE_BUFFER_SIZE-1 downto 0 + k*ELE_3);
                    temp_index := temp_index + 1;
                end loop;               
                for k in 2 to BRAM_BLOCK_WIDTH-BRAM_BLOCK_DEPTH+2  loop
                    CU_image_block(temp_index) <= BRAM_out_buffer(ELE_9-1 + (k-2)*ELE_3 downto 0 + (k-2)*ELE_3);
                    temp_index := temp_index + 1;
                end loop;   
                    -- row-transition-like
                for j in 0 to (KERNEL_LENGTH - 2) loop
                    for k in 0 to BRAM_BLOCK_WIDTH-BRAM_BLOCK_DEPTH  loop
                        CU_image_block(temp_index) <=  
                            BRAM_out_buffer(2*ELE_3+ELE_1-1 + k*ELE_3 + j*ELE_1 downto 2*ELE_3 + k*ELE_3)
                            & temp2(ELE_6-1 + k*ELE_2 downto ELE_4 + k*ELE_2 + j*ELE_1)
                            & BRAM_out_buffer(ELE_4-1 + k*ELE_3 + j*ELE_1 downto ELE_3 + k*ELE_3)
                            & temp2(ELE_4-1 + k*ELE_2 downto ELE_2 + k*ELE_2 + j*ELE_1)
                            & BRAM_out_buffer(ELE_1-1 + k*ELE_3 + j*ELE_1 downto 0 + k*ELE_3)
                            & temp2(ELE_2-1 + k*ELE_2 downto 0 + k*ELE_2 + j*ELE_1);
                        temp_index := temp_index + 1;
                    end loop;
                end loop;        
                temp_index := 0;

                -- Store current BRAM output in image_buffer  
                HORI_image_buffer_next <= HORI_image_buffer;
                for k in 0 to BRAM_BLOCK_WIDTH-1 loop
                    temp(ELE_2-1 + k*ELE_2 downto 0 + k*ELE_2) := BRAM_out_buffer(ELE_3-1 + k*ELE_3 downto ELE_1 + k*ELE_3);
                end loop;
                HORI_image_buffer_next(column_offset-1) <= temp;
                VERT_image_buffer_next <= BRAM_out_buffer(BRAM_DATA_WIDTH-1 downto BRAM_DATA_WIDTH - (VERT_IMAGE_BUFFER_SIZE*DWIDTH) );
                if (prev_column_offset /= column_offset)
                then 
                    COR_image_buffer_next <= temp2(DWIDTH*HORI_IMAGE_BUFFER_SIZE-1 downto DWIDTH*HORI_IMAGE_BUFFER_SIZE - ELE_4);
                else 
                    COR_image_buffer_next <= COR_image_buffer;
                end if;
                
                CU_out_valid_next <= (others => '0');             
                if (prev_column_offset /= column_offset)
                then
                    CU_out_valid_next <= (others => '1');
                else 
                    CU_out_valid_next <= (others => '0');
                end if;
                
            when fin =>
                for k in 0 to CU_NUMBER-1 loop
                    CU_image_block(k) <= (others => '0');
                end loop;
                HORI_image_buffer_next <= HORI_image_buffer;
                VERT_image_buffer_next <= VERT_image_buffer;
                COR_image_buffer_next <= COR_image_buffer;
                CU_out_valid_next <= (others => '0');
                temp_index := 0;
            end case; 
     end process outputs; 

    -- BRAM_receiver
    process(clk,reset)
    begin
        if(reset = '1')
        then
            ctr <= 0;
            column_offset <= 0;
            prev_column_offset <= 0;
            BRAM_we_a <= '0';
            BRAM_addr_a_i <= (others => '0');
            BRAM_din_a <= (others => '0');
            BRAM_out_buffer <= (others => '0');
            new_image_block <= '0';
        elsif(rising_edge(clk))
        then            
            ctr <= ctr + 1;
            new_image_block <= '0';
            prev_column_offset <= column_offset;
            if (ctr = BRAM_CLK_DELAY+1) -- BRAM output data is valid 
            then
                -- Read BRAM output
                BRAM_out_buffer <= signed(BRAM_dout_a);
                -- Set new image block received signal
                new_image_block <= '1';
                
                if (column_offset = IMAGE_LENGTH/BRAM_BLOCK_WIDTH)
                then 
                    column_offset <= 1;
                else 
                    column_offset <= column_offset + 1;
                end if;              
                -- Prepare next address
                if (BRAM_addr_a_i /= IMAGE_LENGTH/BRAM_BLOCK_WIDTH * IMAGE_LENGTH/BRAM_BLOCK_DEPTH-1)
                then 
                    BRAM_addr_a_i <= BRAM_addr_a_i + 1;
                end if;
                -- reset counter 
                ctr <= 1;          
            end if;   
        end if; 
    end process;

BRAM_addr_a <= std_logic_vector(BRAM_addr_a_i);
BRAM_we_a <= '0';

end arch_imp;