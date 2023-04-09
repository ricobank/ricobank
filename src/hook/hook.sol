// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.19;

interface Hook {
    function frobhook(
        address sender, bytes32 i, address u, int dink, int dart
    ) external;

    function grabhook(
        address vow, bytes32 i, address u, uint ink, uint art, uint bill, address payable keeper
    ) external returns (uint);

    function safehook(
        bytes32 i, address u
    ) view external returns (bytes32, uint);
}
