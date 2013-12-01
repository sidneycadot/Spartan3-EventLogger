library ieee;

use ieee.std_logic_1164.all;

entity CalcCRC32 is
    port (
        CLK          : in  std_logic;
        RESET        : in boolean;
        NIBBLE       : in  std_logic_vector(3 downto 0);
        NIBBLE_VALID : in  boolean;
        CRC32_CURR   : out std_logic_vector(31 downto 0); -- sequential output
        CRC32_NEXT   : out std_logic_vector(31 downto 0)  -- combinatorial output
    );
end entity CalcCRC32;

architecture arch of CalcCRC32 is

pure function UpdateCRC(crc : in std_logic_vector(31 downto 0); b : std_logic) return std_logic_vector is
variable update_crc : std_logic_vector(31 downto 0);
variable x : std_logic;
begin
    x := crc(0) xor b;
    update_crc := '1' & crc(31 downto 1);
    if x = '0' then
        update_crc := update_crc xor x"edb88320";
    end if;
    return update_crc;
end function UpdateCRC;

type Registers is record
        crc32 : std_logic_vector(31 downto 0);
    end record Registers;

constant cInitRegisters : Registers := (
        crc32 => (others => '0')
    );

signal rCurrent : Registers := cInitRegisters;

signal sNext : Registers;

begin

    combinatorial : process (rCurrent, RESET, NIBBLE, NIBBLE_VALID) is

    variable vNext : Registers;

    begin

        vNext := rCurrent;

        if RESET then
            vNext.crc32 := (others => '0');
        end if;

        if NIBBLE_VALID then
            -- work from the rightmost bit up.
            for i in 0 to 3 loop
                vNext.crc32 := UpdateCRC(vNext.crc32, NIBBLE(i));
            end loop;
        end if;

        sNext <= vNext;

    end process combinatorial;

    sequential : process (CLK) is
    begin
        if rising_edge(CLK) then
            rCurrent <= sNext;
        end if;
    end process sequential;

    CRC32_CURR <= rCurrent.crc32;
    CRC32_NEXT <= sNext.crc32;

end architecture arch;
