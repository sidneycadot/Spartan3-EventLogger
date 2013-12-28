
library ieee;

use ieee.std_logic_1164.all,
    ieee.numeric_std.all;

-- This implements a 1024-element RAM of 192-bit words.
-- This fits snugly in the BRAM resources available on an XC3S200.

entity BlockRAM is
    port (
        CLK          : in  std_logic;
        ADDR_I       : in  unsigned(1 downto 0);
        DATA_I       : in  std_logic_vector(7 downto 0);
        DATA_I_VALID : in  boolean;
        ADDR_O       : in  unsigned(1 downto 0);
        DATA_O       : out std_logic_vector(7 downto 0)
    );
end entity BlockRAM;

architecture arch of BlockRAM is

type IndexType is range 0 to 1;

type RamType is array(IndexType) of std_logic_vector(7 downto 0);

signal ram : RamType;

signal addressOut : IndexType;

begin

    process (CLK) is
    begin
        if rising_edge(CLK) then
            if DATA_I_VALID then
                ram(IndexType(to_integer(ADDR_I))) <= DATA_I;
            end if;
            addressOut <= IndexType(to_integer(ADDR_O));
        end if;
    end process;

    DATA_O <= ram(addressOut);

end architecture arch;
