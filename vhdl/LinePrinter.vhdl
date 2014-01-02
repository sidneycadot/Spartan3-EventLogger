library ieee;

-- The LinePrinter prints "Events", followed by a 32-bit CRC that is calculated on-the-fly.

use ieee.std_logic_1164.all;

use work.EventLoggerPackage.EventType;

entity LinePrinter is
    port (
        CLK          : in  std_logic;
        RESET        : boolean;
        -- Input is event data
        DATA_I       : in  EventType;
        DATA_I_VALID : in  boolean;
        DATA_I_READY : out boolean;
        -- Output is a sequence of bytes
        DATA_O       : out std_logic_vector(7 downto 0);
        DATA_O_VALID : out boolean;
        DATA_O_READY : in  boolean
    );
end entity LinePrinter;

architecture arch of LinePrinter is

type LinePrinterStateType is (
        -- IDLE state: no data is available.
        IDLE,
        -- print 64-bit sequence number (16 nibbles)
        S_00, S_01, S_02, S_03, S_04, S_05, S_06, S_07, S_08, S_09, S_10, S_11, S_12, S_13, S_14, S_15,
        SPACE_1,
        -- print 64-bit timestamp (16 nibbles)
        T_00, T_01, T_02, T_03, T_04, T_05, T_06, T_07, T_08, T_09, T_10, T_11, T_12, T_13, T_14, T_15,
        SPACE_2,
        -- print 64-bit data vector (16 nibbles)
        D_00, D_01, D_02, D_03, D_04, D_05, D_06, D_07, D_08, D_09, D_10, D_11, D_12, D_13, D_14, D_15,
        SPACE_3,
        -- print 32-bit CRC *8 nibbles)
        C_00, C_01, C_02, C_03, C_04, C_05, C_06, C_07,
        -- Carriage Return followed by Linefeed
        CR, LF
    );

pure function NextLinePrinterState(state : in LinePrinterStateType) return LinePrinterStateType is
begin
    case state is
        when IDLE    => return S_00;
        when S_00    => return S_01;
        when S_01    => return S_02;
        when S_02    => return S_03;
        when S_03    => return S_04;
        when S_04    => return S_05;
        when S_05    => return S_06;
        when S_06    => return S_07;
        when S_07    => return S_08;
        when S_08    => return S_09;
        when S_09    => return S_10;
        when S_10    => return S_11;
        when S_11    => return S_12;
        when S_12    => return S_13;
        when S_13    => return S_14;
        when S_14    => return S_15;
        when S_15    => return SPACE_1;
        when SPACE_1 => return T_00;
        when T_00    => return T_01;
        when T_01    => return T_02;
        when T_02    => return T_03;
        when T_03    => return T_04;
        when T_04    => return T_05;
        when T_05    => return T_06;
        when T_06    => return T_07;
        when T_07    => return T_08;
        when T_08    => return T_09;
        when T_09    => return T_10;
        when T_10    => return T_11;
        when T_11    => return T_12;
        when T_12    => return T_13;
        when T_13    => return T_14;
        when T_14    => return T_15;
        when T_15    => return SPACE_2;
        when SPACE_2 => return D_00;
        when D_00    => return D_01;
        when D_01    => return D_02;
        when D_02    => return D_03;
        when D_03    => return D_04;
        when D_04    => return D_05;
        when D_05    => return D_06;
        when D_06    => return D_07;
        when D_07    => return D_08;
        when D_08    => return D_09;
        when D_09    => return D_10;
        when D_10    => return D_11;
        when D_11    => return D_12;
        when D_12    => return D_13;
        when D_13    => return D_14;
        when D_14    => return D_15;
        when D_15    => return SPACE_3;
        when SPACE_3 => return C_00;
        when C_00    => return C_01;
        when C_01    => return C_02;
        when C_02    => return C_03;
        when C_03    => return C_04;
        when C_04    => return C_05;
        when C_05    => return C_06;
        when C_06    => return C_07;
        when C_07    => return CR;
        when CR      => return LF;
        when LF      => return IDLE;
    end case;
end function NextLinePrinterState;

type Registers is record
        state               : LinePrinterStateType;
        eventToBePrinted    : EventType; -- as received from upstream
        dataInReady         : boolean;
        dataOut             : std_logic_vector(7 downto 0);
        dataOutValid        : boolean;
        checksumReset       : boolean;
        checksumNibble      : std_logic_vector(3 downto 0);
        checksumNibbleValid : boolean;
    end record Registers;

constant cInitRegisters : Registers := (
        state               => IDLE,
        eventToBePrinted    => (sequenceNr => (others => '0'), timestamp => (others => '0'), data => (others => '0')),
        dataInReady         => true,
        dataOut             => (others => '-'),
        dataOutValid        => false,
        checksumReset       => false,
        checksumNibble      => (others => '-'),
        checksumNibbleValid => false
    );

signal rCurrent : Registers := cInitRegisters;

signal sNext : Registers;
signal sChecksum : std_logic_vector(31 downto 0);

begin

    combinatorial : process (rCurrent, DATA_I, DATA_I_VALID, DATA_O_READY) is

    variable vNext : Registers;

    variable vProceed : boolean;
    variable vNibble : std_logic_vector(3 downto 0);

    begin

        vNext := rCurrent;

        -- Determine the next state

        vProceed := false;
        if rCurrent.state = IDLE then
            if DATA_I_VALID then
                -- We can accept an incoming event!
                vProceed := true;
                vNext.eventToBePrinted := DATA_I;
            end if;
        else
            if DATA_O_READY then
                vProceed := true;
            end if;
        end if;

        if vProceed then
            vNext.state := NextLinePrinterState(rCurrent.state);
        end if;

        vNext.checksumReset       := false;
        vNext.checksumNibble      := "----";
        vNext.checksumNibbleValid := false;

        if vProceed then

            -- We are using the print states to calculate the CRC of the concatenation of the
            -- bytes that make up the event data.
            -- Note the order by which we offer the nibbles to the CalcCrc32 entity.
            -- We start with the leftmost byte, and offer the bits with the least-significant
            -- nibble first.

            case vNext.state is

                when S_00 => vNext.checksumNibble := vNext.eventToBePrinted.sequenceNr(59 downto 56); vNext.checksumNibbleValid := true; vNext.checksumReset := true;
                when S_01 => vNext.checksumNibble := vNext.eventToBePrinted.sequenceNr(63 downto 60); vNext.checksumNibbleValid := true;
                when S_02 => vNext.checksumNibble := vNext.eventToBePrinted.sequenceNr(51 downto 48); vNext.checksumNibbleValid := true;
                when S_03 => vNext.checksumNibble := vNext.eventToBePrinted.sequenceNr(55 downto 52); vNext.checksumNibbleValid := true;
                when S_04 => vNext.checksumNibble := vNext.eventToBePrinted.sequenceNr(43 downto 40); vNext.checksumNibbleValid := true;
                when S_05 => vNext.checksumNibble := vNext.eventToBePrinted.sequenceNr(47 downto 44); vNext.checksumNibbleValid := true;
                when S_06 => vNext.checksumNibble := vNext.eventToBePrinted.sequenceNr(35 downto 32); vNext.checksumNibbleValid := true;
                when S_07 => vNext.checksumNibble := vNext.eventToBePrinted.sequenceNr(39 downto 36); vNext.checksumNibbleValid := true;
                when S_08 => vNext.checksumNibble := vNext.eventToBePrinted.sequenceNr(27 downto 24); vNext.checksumNibbleValid := true;
                when S_09 => vNext.checksumNibble := vNext.eventToBePrinted.sequenceNr(31 downto 28); vNext.checksumNibbleValid := true;
                when S_10 => vNext.checksumNibble := vNext.eventToBePrinted.sequenceNr(19 downto 16); vNext.checksumNibbleValid := true;
                when S_11 => vNext.checksumNibble := vNext.eventToBePrinted.sequenceNr(23 downto 20); vNext.checksumNibbleValid := true;
                when S_12 => vNext.checksumNibble := vNext.eventToBePrinted.sequenceNr(11 downto  8); vNext.checksumNibbleValid := true;
                when S_13 => vNext.checksumNibble := vNext.eventToBePrinted.sequenceNr(15 downto 12); vNext.checksumNibbleValid := true;
                when S_14 => vNext.checksumNibble := vNext.eventToBePrinted.sequenceNr( 3 downto  0); vNext.checksumNibbleValid := true;
                when S_15 => vNext.checksumNibble := vNext.eventToBePrinted.sequenceNr( 7 downto  4); vNext.checksumNibbleValid := true;

                when T_00 => vNext.checksumNibble := vNext.eventToBePrinted.timestamp(59 downto 56); vNext.checksumNibbleValid := true;
                when T_01 => vNext.checksumNibble := vNext.eventToBePrinted.timestamp(63 downto 60); vNext.checksumNibbleValid := true;
                when T_02 => vNext.checksumNibble := vNext.eventToBePrinted.timestamp(51 downto 48); vNext.checksumNibbleValid := true;
                when T_03 => vNext.checksumNibble := vNext.eventToBePrinted.timestamp(55 downto 52); vNext.checksumNibbleValid := true;
                when T_04 => vNext.checksumNibble := vNext.eventToBePrinted.timestamp(43 downto 40); vNext.checksumNibbleValid := true;
                when T_05 => vNext.checksumNibble := vNext.eventToBePrinted.timestamp(47 downto 44); vNext.checksumNibbleValid := true;
                when T_06 => vNext.checksumNibble := vNext.eventToBePrinted.timestamp(35 downto 32); vNext.checksumNibbleValid := true;
                when T_07 => vNext.checksumNibble := vNext.eventToBePrinted.timestamp(39 downto 36); vNext.checksumNibbleValid := true;
                when T_08 => vNext.checksumNibble := vNext.eventToBePrinted.timestamp(27 downto 24); vNext.checksumNibbleValid := true;
                when T_09 => vNext.checksumNibble := vNext.eventToBePrinted.timestamp(31 downto 28); vNext.checksumNibbleValid := true;
                when T_10 => vNext.checksumNibble := vNext.eventToBePrinted.timestamp(19 downto 16); vNext.checksumNibbleValid := true;
                when T_11 => vNext.checksumNibble := vNext.eventToBePrinted.timestamp(23 downto 20); vNext.checksumNibbleValid := true;
                when T_12 => vNext.checksumNibble := vNext.eventToBePrinted.timestamp(11 downto  8); vNext.checksumNibbleValid := true;
                when T_13 => vNext.checksumNibble := vNext.eventToBePrinted.timestamp(15 downto 12); vNext.checksumNibbleValid := true;
                when T_14 => vNext.checksumNibble := vNext.eventToBePrinted.timestamp( 3 downto  0); vNext.checksumNibbleValid := true;
                when T_15 => vNext.checksumNibble := vNext.eventToBePrinted.timestamp( 7 downto  4); vNext.checksumNibbleValid := true;

                when D_00 => vNext.checksumNibble := vNext.eventToBePrinted.data(59 downto 56); vNext.checksumNibbleValid := true;
                when D_01 => vNext.checksumNibble := vNext.eventToBePrinted.data(63 downto 60); vNext.checksumNibbleValid := true;
                when D_02 => vNext.checksumNibble := vNext.eventToBePrinted.data(51 downto 48); vNext.checksumNibbleValid := true;
                when D_03 => vNext.checksumNibble := vNext.eventToBePrinted.data(55 downto 52); vNext.checksumNibbleValid := true;
                when D_04 => vNext.checksumNibble := vNext.eventToBePrinted.data(43 downto 40); vNext.checksumNibbleValid := true;
                when D_05 => vNext.checksumNibble := vNext.eventToBePrinted.data(47 downto 44); vNext.checksumNibbleValid := true;
                when D_06 => vNext.checksumNibble := vNext.eventToBePrinted.data(35 downto 32); vNext.checksumNibbleValid := true;
                when D_07 => vNext.checksumNibble := vNext.eventToBePrinted.data(39 downto 36); vNext.checksumNibbleValid := true;
                when D_08 => vNext.checksumNibble := vNext.eventToBePrinted.data(27 downto 24); vNext.checksumNibbleValid := true;
                when D_09 => vNext.checksumNibble := vNext.eventToBePrinted.data(31 downto 28); vNext.checksumNibbleValid := true;
                when D_10 => vNext.checksumNibble := vNext.eventToBePrinted.data(19 downto 16); vNext.checksumNibbleValid := true;
                when D_11 => vNext.checksumNibble := vNext.eventToBePrinted.data(23 downto 20); vNext.checksumNibbleValid := true;
                when D_12 => vNext.checksumNibble := vNext.eventToBePrinted.data(11 downto  8); vNext.checksumNibbleValid := true;
                when D_13 => vNext.checksumNibble := vNext.eventToBePrinted.data(15 downto 12); vNext.checksumNibbleValid := true;
                when D_14 => vNext.checksumNibble := vNext.eventToBePrinted.data( 3 downto  0); vNext.checksumNibbleValid := true;
                when D_15 => vNext.checksumNibble := vNext.eventToBePrinted.data( 7 downto  4); vNext.checksumNibbleValid := true;

                when others => null;

            end case;

        end if; -- We are starting the next state.

        -- determine vNext.dataOut and vNext.dataOutValid

        case vNext.state is

            when S_00 | S_01 | S_02 | S_03 | S_04 | S_05 | S_06 | S_07 | S_08 | S_09 | S_10 | S_11 | S_12 | S_13 | S_14 | S_15 |
                 T_00 | T_01 | T_02 | T_03 | T_04 | T_05 | T_06 | T_07 | T_08 | T_09 | T_10 | T_11 | T_12 | T_13 | T_14 | T_15 |
                 D_00 | D_01 | D_02 | D_03 | D_04 | D_05 | D_06 | D_07 | D_08 | D_09 | D_10 | D_11 | D_12 | D_13 | D_14 | D_15 |
                 C_00 | C_01 | C_02 | C_03 | C_04 | C_05 | C_06 | C_07 =>

                case vNext.state is

                    when S_00 => vNibble := vNext.eventToBePrinted.sequenceNr(63 downto 60);
                    when S_01 => vNibble := vNext.eventToBePrinted.sequenceNr(59 downto 56);
                    when S_02 => vNibble := vNext.eventToBePrinted.sequenceNr(55 downto 52);
                    when S_03 => vNibble := vNext.eventToBePrinted.sequenceNr(51 downto 48);
                    when S_04 => vNibble := vNext.eventToBePrinted.sequenceNr(47 downto 44);
                    when S_05 => vNibble := vNext.eventToBePrinted.sequenceNr(43 downto 40);
                    when S_06 => vNibble := vNext.eventToBePrinted.sequenceNr(39 downto 36);
                    when S_07 => vNibble := vNext.eventToBePrinted.sequenceNr(35 downto 32);
                    when S_08 => vNibble := vNext.eventToBePrinted.sequenceNr(31 downto 28);
                    when S_09 => vNibble := vNext.eventToBePrinted.sequenceNr(27 downto 24);
                    when S_10 => vNibble := vNext.eventToBePrinted.sequenceNr(23 downto 20);
                    when S_11 => vNibble := vNext.eventToBePrinted.sequenceNr(19 downto 16);
                    when S_12 => vNibble := vNext.eventToBePrinted.sequenceNr(15 downto 12);
                    when S_13 => vNibble := vNext.eventToBePrinted.sequenceNr(11 downto  8);
                    when S_14 => vNibble := vNext.eventToBePrinted.sequenceNr( 7 downto  4);
                    when S_15 => vNibble := vNext.eventToBePrinted.sequenceNr( 3 downto  0);

                    when T_00 => vNibble := vNext.eventToBePrinted.timestamp(63 downto 60);
                    when T_01 => vNibble := vNext.eventToBePrinted.timestamp(59 downto 56);
                    when T_02 => vNibble := vNext.eventToBePrinted.timestamp(55 downto 52);
                    when T_03 => vNibble := vNext.eventToBePrinted.timestamp(51 downto 48);
                    when T_04 => vNibble := vNext.eventToBePrinted.timestamp(47 downto 44);
                    when T_05 => vNibble := vNext.eventToBePrinted.timestamp(43 downto 40);
                    when T_06 => vNibble := vNext.eventToBePrinted.timestamp(39 downto 36);
                    when T_07 => vNibble := vNext.eventToBePrinted.timestamp(35 downto 32);
                    when T_08 => vNibble := vNext.eventToBePrinted.timestamp(31 downto 28);
                    when T_09 => vNibble := vNext.eventToBePrinted.timestamp(27 downto 24);
                    when T_10 => vNibble := vNext.eventToBePrinted.timestamp(23 downto 20);
                    when T_11 => vNibble := vNext.eventToBePrinted.timestamp(19 downto 16);
                    when T_12 => vNibble := vNext.eventToBePrinted.timestamp(15 downto 12);
                    when T_13 => vNibble := vNext.eventToBePrinted.timestamp(11 downto  8);
                    when T_14 => vNibble := vNext.eventToBePrinted.timestamp( 7 downto  4);
                    when T_15 => vNibble := vNext.eventToBePrinted.timestamp( 3 downto  0);

                    when D_00 => vNibble := vNext.eventToBePrinted.data(63 downto 60);
                    when D_01 => vNibble := vNext.eventToBePrinted.data(59 downto 56);
                    when D_02 => vNibble := vNext.eventToBePrinted.data(55 downto 52);
                    when D_03 => vNibble := vNext.eventToBePrinted.data(51 downto 48);
                    when D_04 => vNibble := vNext.eventToBePrinted.data(47 downto 44);
                    when D_05 => vNibble := vNext.eventToBePrinted.data(43 downto 40);
                    when D_06 => vNibble := vNext.eventToBePrinted.data(39 downto 36);
                    when D_07 => vNibble := vNext.eventToBePrinted.data(35 downto 32);
                    when D_08 => vNibble := vNext.eventToBePrinted.data(31 downto 28);
                    when D_09 => vNibble := vNext.eventToBePrinted.data(27 downto 24);
                    when D_10 => vNibble := vNext.eventToBePrinted.data(23 downto 20);
                    when D_11 => vNibble := vNext.eventToBePrinted.data(19 downto 16);
                    when D_12 => vNibble := vNext.eventToBePrinted.data(15 downto 12);
                    when D_13 => vNibble := vNext.eventToBePrinted.data(11 downto  8);
                    when D_14 => vNibble := vNext.eventToBePrinted.data( 7 downto  4);
                    when D_15 => vNibble := vNext.eventToBePrinted.data( 3 downto  0);

                    when C_00 => vNibble := sChecksum(31 downto 28);
                    when C_01 => vNibble := sChecksum(27 downto 24);
                    when C_02 => vNibble := sChecksum(23 downto 20);
                    when C_03 => vNibble := sChecksum(19 downto 16);
                    when C_04 => vNibble := sChecksum(15 downto 12);
                    when C_05 => vNibble := sChecksum(11 downto  8);
                    when C_06 => vNibble := sChecksum( 7 downto  4);
                    when C_07 => vNibble := sChecksum( 3 downto  0);

                    when others => vNibble := "----";

                end case;

                case vNibble is
                    when x"0"   => vNext.dataOut := x"30";
                    when x"1"   => vNext.dataOut := x"31";
                    when x"2"   => vNext.dataOut := x"32";
                    when x"3"   => vNext.dataOut := x"33";
                    when x"4"   => vNext.dataOut := x"34";
                    when x"5"   => vNext.dataOut := x"35";
                    when x"6"   => vNext.dataOut := x"36";
                    when x"7"   => vNext.dataOut := x"37";
                    when x"8"   => vNext.dataOut := x"38";
                    when x"9"   => vNext.dataOut := x"39";
                    when x"a"   => vNext.dataOut := x"61";
                    when x"b"   => vNext.dataOut := x"62";
                    when x"c"   => vNext.dataOut := x"63";
                    when x"d"   => vNext.dataOut := x"64";
                    when x"e"   => vNext.dataOut := x"65";
                    when x"f"   => vNext.dataOut := x"66";
                    when others => vNext.dataOut := "--------";
                end case;

            when SPACE_1 | SPACE_2 | SPACE_3 => -- ASCII space characters

                vNext.dataOut := x"20";

            when CR => -- ASCII carriage return character

                vNext.dataOut := x"0d";

            when LF => -- ASCII linefeed character

                vNext.dataOut := x"0a";

            when IDLE =>

                vNext.dataOut := "--------";

        end case; -- determine vNext.dataOut

        -- determine vNext.dataOutValid

        vNext.dataOutValid := (vNext.state /= IDLE);

        -- determine vNext.dataInReady

        vNext.dataInReady := (vNext.state = IDLE);

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

    CalcCrc32_instance : entity CalcCrc32
        port map (
            CLK          => CLK,
            RESET        => rCurrent.checksumReset,
            NIBBLE       => rCurrent.checksumNibble,
            NIBBLE_VALID => rCurrent.checksumNibbleValid,
            CRC32_CURR   => sChecksum,
            CRC32_NEXT   => open
        );

    DATA_I_READY <= rCurrent.dataInReady;
    DATA_O       <= rCurrent.dataOut;
    DATA_O_VALID <= rCurrent.dataOutValid;

end architecture arch;
