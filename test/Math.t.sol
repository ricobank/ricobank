// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.25;

import "forge-std/Test.sol";

import { Math } from "../src/mixin/math.sol";

contract MathTest is Test, Math {
    uint foo;
    int bar;
    function setUp() public {}

    function test_add() public {
        assertEq(add(5, -2), 3);
        assertEq(add(5, 2), 7);
        assertEq(add(0, 0), 0);
        assertEq(add(0, 1), 1);
        assertEq(add(1, 0), 1);

        assertEq(add(type(uint).max - 1, 1), type(uint).max);
        vm.expectRevert(Math.ErrUintOver.selector);
        foo = add(type(uint).max, 1);
        assertEq(add(1, -1), 0);
        vm.expectRevert(Math.ErrUintUnder.selector);
        foo = add(0, -1);
    }

    function test_mul() public {
        assertEq(mul(1, 1), 1);
        assertEq(mul(1, -1), -1);
        assertEq(mul(0, 1), 0);
        assertEq(mul(1, 0), 0);
        assertEq(mul(0, -1), 0);

        // overflow all the way back to same sign and greater magnitude should revert
        vm.expectRevert(Math.ErrIntOver.selector);
        bar = mul(uint(5), type(int).max / 2);
        vm.expectRevert(Math.ErrIntUnder.selector);
        bar = mul(uint(5), -type(int).max / 2);

        assertEq(mul(uint(type(int).max) - 1, 1), type(int).max - 1);
        vm.expectRevert(Math.ErrIntOver.selector);
        bar = mul(uint(type(int).max) + 1, 1);
        vm.expectRevert(Math.ErrIntOver.selector);
        bar = mul(uint(type(int).max) + 1, 2);

        assertEq(mul(uint(type(int).max), 1), type(int).max);
        vm.expectRevert(Math.ErrIntOver.selector);
        bar = mul(uint(type(int).max), 2);
        vm.expectRevert(Math.ErrIntOver.selector);
        bar = mul(uint(type(int).max / 2 + 1), 2);
        vm.expectRevert(Math.ErrUintUnder.selector);
        bar = mul(uint(type(int).max), -1);
        assertEq(mul(uint(type(int).max - 1), -1), type(int).min);
    }

    function test_rmul() public pure {
        assertEq(rmul(RAY, 1), 1);
        assertEq(rmul(RAY, RAY), RAY);
        assertEq(rmul(RAY, 0), 0);
        assertEq(rmul(RAY, 2 * RAY), 2 * RAY);
    }

    function test_rdiv() public {
        assertEq(rdiv(1, RAY), 1);
        assertEq(rdiv(RAY, 1), RAY * RAY);
        assertEq(rdiv(0, RAY), 0);
        vm.expectRevert();
        foo = rdiv(RAY, 0);
        assertEq(rdiv(RAY, RAY / 2), 2 * RAY);
        assertEq(rdiv(RAY, 2 * RAY), RAY / 2);
    }

    function test_rinv() public {
        assertEq(rinv(RAY), RAY);
        assertEq(rinv(2 * RAY), RAY / 2);
        assertEq(rinv(RAY / 2), 2 * RAY);
        vm.expectRevert();
        foo = rinv(0);
    }

    function test_rpow() public pure {
        assertEq(rpow(RAY, 1), RAY);
        assertEq(rpow(RAY, 0), RAY);
        assertEq(rpow(RAY * 2, 2), RAY * 4);
    }

    function test_grow() public pure {
        assertEq(grow(WAD, RAY, 1), WAD);
        assertEq(grow(WAD, RAY, 0), WAD);
        assertEq(grow(WAD * 2, RAY * 2, 1), WAD * 4);
        assertEq(grow(WAD * 2, RAY * 2, 2), WAD * 8);
        assertEq(grow(RAY / BLN, RAY, 5), RAY / BLN);
    }

    function test_rmash() public pure {
        assertEq(rmash(RAY, 0, RAY, 0), RAY);
        assertEq(rmash(RAY, 1, RAY, 0), RAY);
        assertEq(rmash(RAY / 2, 0, RAY, 0), RAY);
        assertEq(rmash(RAY / 2, 1, RAY, 0), RAY / 2);
        assertEq(rmash(RAY / 2, 1, RAY * 2, 0), RAY);
        assertEq(rmash(RAY / 2, 1, RAY / 2, 0), RAY / 4);

        // deal == 0
        assertEq(rmash(0, 1, RAY / 2, int(RAY)), RAY);
        assertEq(rmash(0, 1, RAY / 2, int(RAY / 2)), RAY / 2);
        assertEq(rmash(0, 1, RAY, -int(RAY / 4)), 0);
        assertEq(rmash(0, 1, 2 * RAY, -int(RAY)), 0);

        assertEq(rmash(RAY * 3 / 4, 2, 4 * RAY, -int(RAY)), RAY * 9 / 16 * 4 - RAY);
    }
}
