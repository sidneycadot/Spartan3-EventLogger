library ieee;

use ieee.std_logic_1164.all,
    ieee.numeric_std.all;

entity SynchronousGenericFifo is
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
end entity SynchronousGenericFifo;

architecture arch of SynchronousGenericFifo is

constant NumEntries : positive := 1024;

type IndexType is range 0 to NumEntries - 1;
type CountType is range 0 to NumEntries;

type StorageType is array (IndexType) of std_logic_vector(191 downto 0);

type Registers is record
        head         : IndexType;
        tail         : IndexType;
        count        : CountType;
        dataInReady  : boolean;
        dataOut      : std_logic_vector(191 downto 0);
        dataOutValid : boolean;
    end record Registers;

constant cInitRegisters : Registers := (
        head         => 0, -- points to oldest element
        tail         => 0, -- points to where a new element will go.
        count        => 0,
        dataInReady  => true,
        dataOut      => (others => '0'),
        dataOutValid => false
    );

signal rCurrent : Registers := cInitRegisters;

signal sNext : Registers;

signal sRamWriteAddress   : unsigned(9 downto 0);
signal sRamWriteDataValid : boolean;
signal sRamReadAddress    : unsigned(9 downto 0);

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

        -- Set up data-in ready

        vNext.dataInReady := (vNext.count /= CountType'high);

        -- Set up data out

        if (vNext.count /= 0) then
            vNext.dataOutValid := true;
        else
            vNext.dataOutValid := false;
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

    sRamWriteAddress <= to_unsigned(natural(rCurrent.tail), 10);
    sRamReadAddress  <= to_unsigned(natural(rCurrent.head), 10);

    sRamWriteDataValid <= (rCurrent.count /= CountType'high) and DATA_IN_VALID;

    bram : entity BlockRAM
        port map(
            CLK          => CLK,
            ADDR_I       => sRamWriteAddress,
            DATA_I       => DATA_IN,
            DATA_I_VALID => sRamWriteDataValid,
            ADDR_O       => sRamReadAddress,
            DATA_O       => DATA_OUT
        );

    DATA_IN_READY  <= (rCurrent.count /= CountType'high) and DATA_IN_VALID;
    DATA_OUT_VALID <= (rCurrent.count /= 0);

end architecture arch;
