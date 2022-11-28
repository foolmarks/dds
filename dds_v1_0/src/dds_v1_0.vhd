-----------------------------------------------------------------
--  File        : dds_v1_0.vhd
--  Version     : 1
--  Revision    : 0
--  Date        : 12.03.2017
--  Author      : Mark Harvey
--  Description : Direct Digital Synthesis top level
------------------------------------------------------------------

library ieee ;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity dds_v1_0 is
  generic (
    RESET_POLARITY : std_logic := '1';               -- reset polarity, 1 = active hi, 0 = active lo
    SINE_TABLE     : integer := 16                   -- sine LUT table address bits, 16 or 12 only
 );             
  port (
    CLK       : in  std_logic;                       -- clock
    CE        : in  std_logic;                       -- active hi load for tuuuning word (PHASEINC)
    RST       : in  std_logic;                       -- sync reset, active hi
    PHASEINC  : in  std_logic_vector(31 downto 0);   -- phase increment word/tuning word
    SINOUT    : out std_logic_vector(15 downto 0);   -- sine wave out
    COSOUT    : out std_logic_vector(15 downto 0);   -- cosine wave out
    SQUAREOUT : out std_logic_vector(15 downto 0)    -- square wave out
    );
end entity dds_v1_0;

architecture arc_dds of dds_v1_0 is


    -- sine lookup table ROM
    component dpROM12_v1_0 is
    port (
      CLK        : in  std_logic;          
      ADDRESS_A  : in  std_logic_vector;
      DATAOUT_A  : out std_logic_vector;
      ADDRESS_B  : in  std_logic_vector;
      DATAOUT_B  : out std_logic_vector
     );
    end component dpROM12_v1_0;
    
    -- sine lookup table ROM
    component dpROM16_v1_0 is
    port (
     CLK        : in  std_logic;          
     ADDRESS_A  : in  std_logic_vector;
     DATAOUT_A  : out std_logic_vector;
     ADDRESS_B  : in  std_logic_vector;
     DATAOUT_B  : out std_logic_vector
    );
    end component dpROM16_v1_0;
    
    

    -- internal signals
    signal tuningWord_reg     : std_logic_vector(31 downto 0) := (others => '0');
    signal phaseAccum         : unsigned(31 downto 0) := (others => '0');
    signal ditherWord         : unsigned(31 downto 0) := (others => '0');
    signal lfsrWord           : unsigned(31 downto 0) := x"00000001";
    signal addrDelay          : std_logic_vector(31 downto 30) := "00";
    signal addrDelay1         : std_logic_vector(31 downto 30) := "00";
    signal addrDelay2         : std_logic_vector(31 downto 30) := "00";
    signal romAddr_sin        : std_logic_vector(SINE_TABLE-3 downto 0) ;  -- 14bits for 16bit table, 10 bits for 12bit table
    signal romAddr_cos        : std_logic_vector(SINE_TABLE-3 downto 0) ;  -- 14bits for 16bit table, 10 bits for 12bit table
    signal sine               : std_logic_vector(15 downto 0) ;
    signal cosine             : std_logic_vector(15 downto 0) ;
    signal reset_async        : std_logic;
    signal resetSync0         : std_logic := '1';
    signal resetSync1         : std_logic := '1';
    signal reset              : std_logic := '1';
    signal sine_invert        : std_logic_vector(15 downto 0) ;
    signal sine_2s_comp       : unsigned(15 downto 0) ;
    signal sinewave           : std_logic_vector(15 downto 0) := (others => '0');
    signal cos_invert         : std_logic_vector(15 downto 0) ;
    signal cos_2s_comp        : unsigned(15 downto 0) ;
    signal coswave            : std_logic_vector(15 downto 0) := x"7FFF";
    signal sqrwave            : std_logic_vector(15 downto 0) := x"8000";
    
    
    -- xilinx specific attribute to implement phase accumulator in DSP48
--    attribute use_dsp48 : string;
--    attribute use_dsp48 of phaseAccum : signal is "yes";
--    attribute use_dsp48 of ditherWord : signal is "no";
    
begin

  -- check SINE_TABLE generic is set correctly; only legal values are 12 and 16
  assert (SINE_TABLE = 16 or SINE_TABLE = 12) report "**** SINE_TABLE generic must be set to 12 or 16 ****" severity failure;
    
    
  ------------------------------------------------------------------
  --   internal reset
  ------------------------------------------------------------------
  -- external reset is considered asynchronous and so must 
  -- be synch'd to CLK internally

   gen0: if (RESET_POLARITY = '0') generate
      begin
         reset_async <= not(RST);
   end generate;
   
   gen1: if (RESET_POLARITY = '1') generate
      begin
         reset_async <= RST;
   end generate;
   
   process (CLK, reset_async)
   begin
     if (reset_async = '1') then
       resetSync0 <= '1';
       resetSync1 <= '1';
       reset      <= '1';       
     elsif (CLK'event and CLK = '1') then
       resetSync0 <= '0';
       resetSync1 <= resetSync0;
       reset      <= resetSync1;     
     end if;  
   end process;
   

  ------------------------------------------------------------------
  -- 32bit Phase Accumulator
  -- For a 16bit address LUT, the phase accum has 16 fractional bits (15:0)
  -- For a 12bit address LUT, the phase accum has 20 fractional bits (19:0)
  ------------------------------------------------------------------

 -- load tuning word to internal register
  process (CLK)
  begin
    if (CLK'event and CLK = '1') then
      if (reset = '1') then
        tuningWord_reg <= (others => '0');
      elsif (CE = '1') then
       tuningWord_reg <= PHASEINC;
      end if;
    end if;

  end process;

  -- the phase accumulator
  process (CLK)
  begin
    if (CLK'event and CLK = '1') then
      if (reset = '1') then
        phaseAccum <= (others => '0');
      else
       phaseAccum <= phaseAccum + unsigned(tuningWord_reg);
      end if;
    end if;

  end process;


  
  ------------------------------------------------------------------
  -- Phase dithering
  -- A pseudo-random value is generated by a maximal length
  -- Linear Feedback Shift Register which is added to the fractional
  -- bits of the phase accumulator
  ------------------------------------------------------------------

  gen2: if (SINE_TABLE = 16) generate
    begin
        
      -- maximal length 16bit LFSR
      process (CLK)
      begin
        if (CLK'event and CLK = '1') then
          lfsrWord(15 downto 1) <= lfsrWord(14 downto 0);
          lfsrWord(0) <= lfsrWord(1) xor lfsrWord(2) xor lfsrWord(4) xor lfsrWord(15);
        end if;
       end process;
        
  end generate;



 gen3: if (SINE_TABLE = 12) generate
    begin
    
      -- maximal length 20bit LFSR
      process (CLK)
      begin
        if (CLK'event and CLK = '1') then
          lfsrWord(19 downto 1) <= lfsrWord(18 downto 0);
          lfsrWord(0) <= lfsrWord(2) xor lfsrWord(19);
        end if;
       end process;

  end generate;

 
   -- add LFSR to phase accumulator output
   process (CLK)
   begin
     if (CLK'event and CLK = '1') then       
       if (reset = '1') then
         ditherWord <= (others => '0');
       else
         ditherWord <= phaseAccum + lfsrWord;
       end if;       
     end if;
     
   end process;   

   
  
  process (CLK)
  begin
    if (CLK'event and CLK = '1') then
      if (reset = '1') then
        addrDelay1      <= "00";
        addrDelay2      <= "00";
        addrDelay       <= "00";
      else
        addrDelay1  <= std_logic_vector(phaseAccum(31 downto 30));
        addrDelay2  <= addrDelay1;
        addrDelay   <= addrDelay2;
      end if;
    end if;
  end process;
  


  ------------------------------------------------------------------
  -- Sine table address
  -- The quadrant of the sine wave is selected by the 2 MS bits
  -- of the dithered phase accumulator.
  
  -- ditherWord (31:30)         quadrant
  ---------------------------------------------
  --       00                 0     -> pi/2
  --       01                 pi/2  -> pi
  --       10                 pi    -> 3pi/2
  --       10                 3pi/2 -> 2pi
  ------------------------------------------------------------------
  
  gen4: if (SINE_TABLE = 16) generate
  begin
    process (ditherWord)
    begin
      for i in 0 to 13 loop
        romAddr_sin(i) <= ditherWord(i+16) xor ditherWord(30);
        romAddr_cos(i) <= ditherWord(i+16) xor (not(ditherWord(30)));
      end loop;
    end process;
  end generate;

  
  gen5: if (SINE_TABLE = 12) generate
  begin
    process (ditherWord)
    begin
      for i in 0 to 9 loop
        romAddr_sin(i) <= ditherWord(i+20) xor ditherWord(30);
        romAddr_cos(i) <= ditherWord(i+20) xor (not(ditherWord(30)));
      end loop;
    end process;
  end generate;


  ------------------------------------------------------------------
  --   Sine Look-up table
  ------------------------------------------------------------------
  -- sine look-up table is a quarter-wave table to reduce memory requirements
  -- the ROM is dual-port to allow both sine & cosine to be generated

   gen6: if (SINE_TABLE = 12) generate
   begin
   
     U0 : dpROM12_v1_0
      port map (
        CLK       => CLK,
        ADDRESS_A => romAddr_sin,
        DATAOUT_A => sine,
        ADDRESS_B => romAddr_cos,
        DATAOUT_B => cosine
   );
   end generate;
   

   gen7: if (SINE_TABLE = 16) generate
   begin
   
     U0 : dpROM16_v1_0
      port map (
        CLK       => CLK,
        ADDRESS_A => romAddr_sin,
        DATAOUT_A => sine,
        ADDRESS_B => romAddr_cos,
        DATAOUT_B => cosine
   );
   end generate;
   


  ------------------------------------------------------------------
   --  2s Complement of sine output
   ------------------------------------------------------------------
 
   sine_invert <= not(sine);
   sine_2s_comp <= unsigned(sine_invert) + 1;
 
   process (CLK)
   begin
     if (CLK'event and CLK = '1') then
     
       if (reset = '1') then
         sinewave <= (others => '0');    
       elsif (addrDelay(31) = '1') then
         sinewave <= std_logic_vector(sine_2s_comp);
       else
        sinewave <= sine;
       end if;
       
     end if;
   end process;
   
   SINOUT <= sinewave;
   
   
  ------------------------------------------------------------------
   --  2s Complement of cosine output
   ------------------------------------------------------------------
 
   cos_invert <= not(cosine);
   cos_2s_comp <= unsigned(cos_invert) + 1;
 
   process (CLK)
   begin
     if (CLK'event and CLK = '1') then
     
       if (reset = '1') then
         coswave <= x"7FFF";    
       elsif ((addrDelay(31) xor addrDelay(30)) = '1') then
         coswave <= std_logic_vector(cos_2s_comp);
       else
        coswave <= cosine;
       end if;
       
     end if;
   end process;
   
   COSOUT <= coswave;
   
  ------------------------------------------------------------------
  --   Square Wave output
  ------------------------------------------------------------------
  
  process (CLK)
  begin
    if (CLK'event and CLK = '1') then
    
      if (reset = '1') then
        sqrwave <= x"8000";        
      elsif (addrDelay(31) = '0') then
        sqrwave <= x"8000";      
     elsif (addrDelay(31) = '1') then
        sqrwave <= x"7FFF";      
      end if;
      
    end if;
  end process;

  SQUAREOUT <= sqrwave;
  
  
  
  
end architecture arc_dds;
-----------------------------------------------------------------
--  End of File: dds_v1_0.vhd
-----------------------------------------------------------------
