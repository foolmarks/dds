-----------------------------------------------------------------
--  File: tb_dds.sv
------------------------------------------------------------------

library ieee ;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;


entity tb_dds is
end entity tb_dds;


architecture tb_arc_dds of tb_dds is

  component dds_v1_0 is
    generic (
      RESET_POLARITY : std_logic := '1';               -- reset polarity, 1 = acive hi, 0 = active lo
      SINE_TABLE     : integer := 16                   -- sine LUT table address bits, 16 or 12 only
      );             
    port (
      CLK       : in  std_logic;                       -- clock
      CE        : in  std_logic;                       -- clock enable, active hi
      RST       : in  std_logic;                       -- sync reset, active hi
      PHASEINC  : in  std_logic_vector(31 downto 0);   -- phase increment word
      SINOUT    : out std_logic_vector(15 downto 0);   -- sine wave out
      COSOUT    : out std_logic_vector(15 downto 0);   -- cosine wave out
      SQUAREOUT : out std_logic_vector(15 downto 0)    -- square wave out
      );
   end component dds_v1_0;


    -- internal signals
    signal tbClk        : std_logic := '0';
    signal tbReset      : std_logic := '1';
    signal tbCE         : std_logic := '0';
    type   array_t is array (0 to 2) of std_logic_vector(31 downto 0); 
    signal tbPhsIncArray: array_t := (x"00F0F006", x"000E0000", x"0FF00001");
    signal tbPhsInc     : std_logic_vector(31 downto 0) := (others => '0');
    signal tbSine       : std_logic_vector(15 downto 0);
    signal tbCos        : std_logic_vector(15 downto 0);
    signal tbSqr        : std_logic_vector(15 downto 0);
    constant cClkPeriod : time := 2 ns;


begin




  ------------------------------------------------------------------
  --   generate the clock & reset
  ------------------------------------------------------------------
  tbClk <= not(tbClk) after (cClkPeriod/2);  
  tbReset <= '0' after 250 ns;
   
   
  ------------------------------------------------------------------
  --   Instantiate UUT
  ------------------------------------------------------------------

  UUT : dds_v1_0
    generic map(
      RESET_POLARITY => '1',
      SINE_TABLE     => 16 )
    port map (
       CLK       => tbClk,
       CE        => tbCE,
       RST       => tbReset,
       PHASEINC  => tbPhsInc,
       SINOUT    => tbSine,
       COSOUT    => tbCos,
       SQUAREOUT => tbSqr   );


  ------------------------------------------------------------------
  --   measure output period of square wave
  ------------------------------------------------------------------
  process
  
    variable vTime      : time := 0 ps;
    variable vPeriodMax : time := 0 ps;
    variable vPeriodMin : time := 0 ps;
    variable vMinFoundAt : time := 0 ps;
    variable vMaxFoundAt : time := 0 ps;
    
    variable vClkPeriod         : real := 0.000000;
    variable vPhaseInc          : integer := 0;
    variable vDenominator       : real := 0.000000;
    constant vNumerator         : real := 4294967296.0;
    variable vExpectedClkPeriod : real := 0.0;
    
    
  begin
    wait until (tbReset'event and tbReset = '0');
    
    -- wait for internal reset to be released
    for i in 0 to 10 loop
      wait until (tbClk'event and tbClk = '1'); 
    end loop;
    
    
    for j in 0 to 2 loop
    
      tbPhsInc <= tbPhsIncArray(j);
      wait until (tbClk'event and tbClk = '1'); 
      tbCE <= '1';
      wait until (tbClk'event and tbClk = '1'); 
      tbCE <= '0';
    
      for i in 0 to 99 loop
      
        wait until (tbSqr(15)'event and tbSqr(15) = '1');  -- wait for rising edge 
        vTime := now;
        wait until (tbSqr(15)'event and tbSqr(15) = '1');  -- wait for next rising edge
        vTime := now - vTime;
        
        if (i = 0) then
          vPeriodMin := vTime;
          vPeriodMax := vTime;
          vMinFoundAt := now;
          vMaxFoundAt := now;
        elsif (vTime > vPeriodMax) then
          vPeriodMax := vTime;
          vMaxFoundAt := now;
        elsif (vTime < vPeriodMin) then
          vPeriodMin := vTime;
          vMinFoundAt := now;
        end if;           
      
      end loop;
         
    -- report measured output period
    report "TB: Max period = " & time'image(vPeriodMax) & " ps found at " & time'image(vMaxFoundAt) & ".  Min period = " & time'image(vPeriodMin) & " ps found at " & time'image(vMinFoundAt) & ".";
    
    -- calc expected output period     
    vPhaseInc := to_integer(unsigned(tbPhsInc));    
    vDenominator := (1.0000000 / real(cClkPeriod / 1 ps)) * real(vPhaseInc);    
    vExpectedClkPeriod := vNumerator / vDenominator;
    
    report "TB: Expected Clock period = " & real'image(vExpectedClkPeriod) & " ps";
    
    end loop;
     
    
     report "TB: ********** FINISHED SIMULATION **********";
     stop(0);
     
  end process;
  
   
end architecture tb_arc_dds;
-----------------------------------------------------------------
--  End of File: tb_dds.vhd
-----------------------------------------------------------------
