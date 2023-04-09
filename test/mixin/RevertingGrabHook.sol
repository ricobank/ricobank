// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

contract RevertingGrabHook {

    function frobhook(
        address, bytes32, address, int, int
    ) public pure {
        return;
    }

    function grabhook(
        address, bytes32, address, uint, uint, uint, address payable
    ) public pure returns (uint) {
        revert('grab revert');
    }

    function safehook(
        bytes32, address
    ) pure external returns (bytes32, uint){return(bytes32(uint(1000 * 10 ** 27)), type(uint256).max);}
}

contract CorrectlyMisbehavingGrabHook {

    function frobhook(
        address, bytes32, address, int, int
    ) public pure {
        return;
    }

    function grabhook(
        address, bytes32, address, uint, uint, uint, address payable
    ) public pure returns (bytes32 oneword) {
        return bytes32(bytes4("bad2")); // one word
    }

    function safehook(
        bytes32, address
    ) pure external returns (bytes32, uint){return(bytes32(uint(1000 * 10 ** 27)), type(uint256).max);}

}

contract IncorrectlyMisbehavingGrabHook {
    function frobhook(
        address, bytes32, address, int, int
        ) public pure {
            return;
    }

    function grabhook(
        address, bytes32, address, uint, uint, uint, address payable
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

    function safehook(
        bytes32, address
    ) pure external returns (bytes32, uint){return(bytes32(uint(1000 * 10 ** 27)), type(uint256).max);}
}
