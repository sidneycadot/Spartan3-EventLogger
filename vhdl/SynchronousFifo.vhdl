library ieee;

use ieee.std_logic_1164.all,
    ieee.numeric_std.all;

use work.EventTypePackage.all;

entity SynchronousFifo is
    port (
        CLK            : in  std_logic;
        RESET          : in  boolean;
        DATA_IN        : in  EventType;
        DATA_IN_VALID  : in  boolean;
        DATA_IN_READY  : out boolean;
        DATA_OUT       : out EventType;
        DATA_OUT_VALID : out boolean;
        DATA_OUT_READY : in  boolean
    );
end entity SynchronousFifo;

architecture arch of SynchronousFifo is

constant NumEntries : positive := 5;

type IndexType is range 0 to NumEntries - 1;
type CountType is range 0 to NumEntries;

type StorageType is array (IndexType) of EventType;

type Registers is record
        storage      : StorageType;
        head         : IndexType;
        tail         : IndexType;
        count        : CountType;
        dataInReady  : boolean;
        dataOut      : EventType;
        dataOutValid : boolean;
    end record Registers;

constant cInitRegisters : Registers := (
        storage      => (others => cNullEvent),
        head         => 0, -- points to oldest element
        tail         => 0, -- points to where a new element will go.
        count        => 0,
        dataInReady  => true,
        dataOut      => cNullEvent,
        dataOutValid => false
    );

signal rCurrent : Registers := cInitRegisters;

signal sNext : Registers;

begin

    combinatorial : process (rCurrent, DATA_IN, DATA_IN_VALID, DATA_OUT_READY) is

    variable vNext : Registers;

    begin

        vNext := rCurrent;

        -- remove output if accepted

        if vNext.count /= 0 and DATA_OUT_READY then

            if vNext.head = IndexType'high then
                vNext.head := 0;
            else
                vNext.head := vNext.head + 1;
            end if;

            vNext.count := vNext.count - 1;

        end if;

        -- take input if there is room

        if vNext.count /= CountType'high and DATA_IN_VALID then

            vNext.storage(vNext.tail) := DATA_IN;

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
            vNext.dataOut := vNext.storage(vNext.head);
            vNext.dataOutValid := true;
        else
            vNext.dataOut := cNullEvent;
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

    DATA_IN_READY  <= rCurrent.dataInReady;
    DATA_OUT       <= rCurrent.dataOut;
    DATA_OUT_VALID <= rCurrent.dataOutValid;

end architecture arch;
