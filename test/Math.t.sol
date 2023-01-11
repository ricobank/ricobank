// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import { Math } from "../src/mixin/math.sol";

contract MathTest is Test, Math {
    function setUp() public {}

    function test_add() public {
        assertEq(add(5, -2), 3);
    }

    function test_rpow() public {
        assertEq(rpow(RAY, 1), RAY);
        assertEq(rpow(RAY, 0), RAY);
        assertEq(rpow(RAY * 2, 2), RAY * 4);
    }

    function test_grow() public {
        assertEq(grow(WAD, RAY, 1), WAD);
        assertEq(grow(WAD, RAY, 0), WAD);
        assertEq(grow(WAD * 2, RAY * 2, 1), WAD * 4);
        assertEq(grow(WAD * 2, RAY * 2, 2), WAD * 8);
        assertEq(grow(RAY / BLN, RAY, 5), RAY / BLN);
    }
}
