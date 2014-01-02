
-- The BlockRam entity implements a 1024-element RAM of 192-bit words.
-- This fits comfortably in the BRAM resources available on an XC3S200.

-- We implement a SYNCHRONOUS ram:
--
-- (1) On the input (write) side, the RAM is updated at the up-edge of the clock
-- (2) On the output (read) side, the ADDR_O is registered on the up-edge of the clock,
--     and the DATA_O continuously reflects the RAM at the registered address.
--
-- Note that thhe entity and architecture definitions given below follow the examples
-- given in the XST manual. This allows XST to infer a block RAM solution for this entity.

library ieee;

use ieee.std_logic_1164.all,
    ieee.numeric_std.all;

entity BlockRam is
    port (
        CLK          : in  std_logic;
        ADDR_I       : in  unsigned(9 downto 0);
        DATA_I       : in  std_logic_vector(191 downto 0);
        DATA_I_VALID : in  boolean;
        ADDR_O       : in  unsigned(9 downto 0);
        DATA_O       : out std_logic_vector(191 downto 0)
    );
end entity BlockRam;

architecture arch of BlockRam is

type IndexType is range 0 to 1023;

type RamType is array(IndexType) of std_logic_vector(191 downto 0);

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
