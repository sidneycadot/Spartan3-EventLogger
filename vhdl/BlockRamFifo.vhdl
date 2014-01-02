
library ieee;

use ieee.std_logic_1164.all,
    ieee.numeric_std.all;

entity BlockRamFifo is
    port (
        CLK            : in  std_logic;
        RESET          : in  boolean;
        DATA_IN        : in  std_logic_vector(191 downto 0);
        DATA_IN_VALID  : in  boolean;
        DATA_IN_READY  : out boolean;
        DATA_OUT       : out std_logic_vector(191 downto 0);
        DATA_OUT_VALID : out boolean;
        DATA_OUT_READY : in  boolean
    );
end entity BlockRamFifo;

architecture arch of BlockRamFifo is

constant NumEntries : positive := 1024;

type IndexType is range 0 to NumEntries - 1;
type CountType is range 0 to NumEntries;

type Registers is record
        head  : IndexType;
        tail  : IndexType;
        count : CountType;
    end record Registers;

constant cInitRegisters : Registers := (
        head         => 0, -- points to oldest element
        tail         => 0, -- points to where a new element will go.
        count        => 0
    );

signal rCurrent : Registers := cInitRegisters;

signal sNext : Registers;

signal sHeadAddress : unsigned(9 downto 0);
signal sTailAddress : unsigned(9 downto 0);

signal sRamWriteDataValid : boolean;

begin

    combinatorial : process (rCurrent, DATA_IN, DATA_IN_VALID, DATA_OUT_READY, RESET) is

    variable vNext : Registers;

    begin

        vNext := rCurrent;

        -- remove head element if our output side signals it accepted the data.

        if vNext.count /= 0 and DATA_OUT_READY then

            -- increment 'head' of the circular buffer (dropping the head element)
            if vNext.head = IndexType'high then
                vNext.head := 0;
            else
                vNext.head := vNext.head + 1;
            end if;

            vNext.count := vNext.count - 1;

        end if;

        -- accept input if our input side signals availability, and there is room.
        -- The new data goes to the tail of the FIFO queue.

        if vNext.count /= CountType'high and DATA_IN_VALID then

            -- signal RAM that it should store the data

            -- increment 'tail' of the circular buffer
            if vNext.tail = IndexType'high then
                vNext.tail := 0;
            else
                vNext.tail := vNext.tail + 1;
            end if;

            vNext.count := vNext.count + 1;

        end if;

        if RESET then
            vNext := cInitRegisters;
        end if;

        sNext <= vNext;

    end process combinatorial;

    sequential : process (CLK) is
    begin
        if rising_edge(CLK) then
            rCurrent <= sNext;
        end if;
    end process sequential;

    sHeadAddress <= to_unsigned(natural(rCurrent.head) - 1, 10);
    sTailAddress <= to_unsigned(natural(rCurrent.tail), 10);

    sRamWriteDataValid <= (rCurrent.count /= CountType'high) and DATA_IN_VALID;

    BlockRam_instance : entity BlockRam
        port map(
            CLK          => CLK,
            ADDR_I       => sTailAddress,
            DATA_I       => DATA_IN,
            DATA_I_VALID => sRamWriteDataValid,
            ADDR_O       => sHeadAddress,
            DATA_O       => DATA_OUT
        );

    DATA_IN_READY  <= (rCurrent.count /= CountType'high) and DATA_IN_VALID;
    DATA_OUT_VALID <= (rCurrent.count /= 0);

end architecture arch;
