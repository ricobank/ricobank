// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021-2023 halys

pragma solidity ^0.8.19;

interface Hook {
    function frobhook(
        address sender, bytes32 i, address u, bytes calldata dink, int dart
    ) external returns (bool safer);
    function bailhook(
        bytes32 i, address u, uint bill, address keeper, uint rush
    ) external returns (bytes memory);
    function safehook(
        bytes32 i, address u
    ) view external returns (uint, uint);
    function ink(bytes32 i, address u) external view returns (bytes memory);
}
