// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

contract RevertingGrabHook {

    function frobhook(
        address, bytes32, address, int, int
    ) public pure {
        return;
    }

    function grabhook(
        address, bytes32, address, uint, uint, uint
    ) public pure returns (uint) {
        revert('grab revert');
    }

}

contract CorrectlyMisbehavingGrabHook {

    function frobhook(
        address, bytes32, address, int, int
    ) public pure {
        return;
    }

    function grabhook(
        address, bytes32, address, uint, uint, uint
    ) public pure returns (bytes32 oneword) {
        return bytes32(bytes4("bad2")); // one word
    }

}

contract IncorrectlyMisbehavingGrabHook {
    function frobhook(
        address, bytes32, address, int, int
        ) public pure {
            return;
    }

    function grabhook(
        address, bytes32, address, uint, uint, uint
    ) public pure returns (bytes memory long) {
        long = new bytes(64);
        long[0] = 'r';
        long[1] = 'i';
        long[2] = 'c';
        long[3] = 'o';
        long[63] = 'b';
        long[62] = 'a';
        long[61] = 'n';
        long[60] = 'k';
    }

}