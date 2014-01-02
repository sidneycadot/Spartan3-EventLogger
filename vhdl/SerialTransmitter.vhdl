library ieee;

use ieee.std_logic_1164.all,
    ieee.numeric_std.all;

entity SerialTransmitter is
    port (
        CLK         : in  std_logic;
        -- Synchronous reset
        RESET       : in  boolean;
        -- Data that we must output over the serial line
        OCTET       : in  std_logic_vector(7 downto 0);
        OCTET_VALID : in  boolean;
        OCTET_READY : out boolean;
        -- The serial line (e.g. RS-232)
        SERIAL_OUT  : out std_logic
    );
end entity SerialTransmitter;

architecture arch of SerialTransmitter is

type SerialTransmitterStateType is (Start, Bit0, Bit1, Bit2, Bit3, Bit4, Bit5, Bit6, Bit7, StopNoData, StopData);

pure function NextTransmitterState(state : in SerialTransmitterStateType) return SerialTransmitterStateType is
begin
    case state is
        when Start      => return Bit0;
        when Bit0       => return Bit1;
        when Bit1       => return Bit2;
        when Bit2       => return Bit3;
        when Bit3       => return Bit4;
        when Bit4       => return Bit5;
        when Bit5       => return Bit6;
        when Bit6       => return Bit7;
        when Bit7       => return StopNoData;
        when StopNoData => return StopData;
        when StopData   => return Start;
    end case;
end function NextTransmitterState;

-- Note that explicit type conversion from real to integer rounds to the nearest integer, as desired.
-- Having the calculation on the right-hand side causes compile time problem in XST,
-- so we give the calculated value explicitly here.

constant HoldCounterPeriod : natural := 434; -- natural(50000000.0 / 115200.0);

type HoldCounterType is range 0 to HoldCounterPeriod - 1;

type Registers is record
        state       : SerialTransmitterStateType;
        holdCounter : HoldCounterType;
        octet       : std_logic_vector(7 downto 0);
        -- registered outputs
        octetReady  : boolean;
        serialOut   : std_logic;
    end record Registers;

constant cInitRegisters : Registers := (
        state       => StopNoData,
        holdCounter => 0,
        octet       => "--------",
        octetReady  => true,
        serialOut   => '1'
    );

signal rCurrent : Registers := cInitRegisters;
signal sNext : Registers;

begin

    combinatorial : process (rCurrent, RESET, OCTET, OCTET_VALID) is

    variable vNext : Registers;

    begin

        vNext := rCurrent;

        case rCurrent.state is
            when Start | Bit0 | Bit1 | Bit2 | Bit3 | Bit4 | Bit5 | Bit6 | StopData =>
                if vNext.holdCounter = 0 then
                    vNext.holdCounter := HoldCounterType'high;
                    vNext.state := NextTransmitterState(rCurrent.state);
                else
                    vNext.holdCounter := vNext.holdCounter - 1;
                end if;
            when Bit7 =>
                if vNext.holdCounter = 0 then
                    vNext.holdCounter := HoldCounterType'high;
                    if OCTET_VALID then
                        vNext.octet := OCTET;
                        vNext.state := StopData;
                    else
                        vNext.state := StopNoData;
                    end if;
                else
                    vNext.holdCounter := vNext.holdCounter - 1;
                end if;
            when StopNoData =>
                if vNext.holdCounter = 0 then
                    if OCTET_VALID then
                        vNext.holdCounter := HoldCounterType'high;
                        vNext.octet := OCTET;
                        vNext.state := Start;
                    end if;
                else
                    if OCTET_VALID then
                        vNext.octet := OCTET;
                        vNext.state := StopData;
                    end if;
                    vNext.holdCounter := vNext.holdCounter - 1;
                end if;
        end case;

        -- On the next clock cycle, will we accept OCTET if it is offered?
        vNext.octetReady := (vNext.state = Bit7 and vNext.holdCounter = 0) or (vNext.state = StopNoData);

        case vNext.state is
            when Start                 => vNext.serialOut := '0';
            when Bit0                  => vNext.serialOut := vNext.octet(0);
            when Bit1                  => vNext.serialOut := vNext.octet(1);
            when Bit2                  => vNext.serialOut := vNext.octet(2);
            when Bit3                  => vNext.serialOut := vNext.octet(3);
            when Bit4                  => vNext.serialOut := vNext.octet(4);
            when Bit5                  => vNext.serialOut := vNext.octet(5);
            when Bit6                  => vNext.serialOut := vNext.octet(6);
            when Bit7                  => vNext.serialOut := vNext.octet(7);
            when StopData | StopNoData => vNext.serialOut := '1';
         end case;

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

    SERIAL_OUT  <= rCurrent.serialOut;
    OCTET_READY <= rCurrent.octetReady;

end architecture arch;
