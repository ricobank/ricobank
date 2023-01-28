// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import { RicoSetUp } from "./RicoHelper.sol";
import { Gem } from '../lib/gemfab/src/gem.sol';

contract VoxTest is Test, RicoSetUp {
    uint256 public init_join = 1000;
    uint stack = WAD * 10;
    bytes32[] ilks;
    bytes32 pool_id_rico_risk;
    bytes32 pool_id_gold_rico;

    function setUp() public {
        make_bank();
        vox.file(bytes32('tag'), rtag);
        vox.file(bytes32('cap'), bytes32(3 * RAY));
        vat.prod(7 * WAD);
    }

    function test_sway() public {
        feed.push(rtag, bytes32(7 * WAD), block.timestamp + 1000);

        skip(100);
        vox.poke();
        assertEq(vat.par(), 7 * WAD);

        vox.file(bytes32('way'), bytes32(2 * RAY));
        skip(2);
        vox.poke();
        assertEq(vat.par(), 28 * WAD);
    }

    function test_ricolike_vox() public {
        vox.poke(); // how == way == 1, par stuck at 7
        uint how = RAY + (RAY * 12 / 10) / (10 ** 16);
        vox.file(bytes32('how'), bytes32(how));
        feed.push(rtag, bytes32(1 * WAD), 10 ** 12);

        vox.poke(); // no time has passed
        assertEq(vat.par(), 7 * WAD);
        skip(1);
        vox.poke();
        assertEq(vat.par(), 7 * WAD); // way *= how, par will increase next

        skip(1);
        vox.poke();
        uint expectedpar2 = 7 * WAD * how / RAY;
        assertEq(vat.par(), expectedpar2); // way > 1 -> par increases

        skip(1);
        feed.push(rtag, bytes32(10 * WAD), 10 ** 12); // raise mar above par
        vox.poke(); // poke updates par before way, par should increase again
        // this time it's multiplied by how ** 2
        uint expectedpar3 = 7 * WAD * how / RAY * how / RAY * how / RAY;
        assertEq(vat.par(), expectedpar3);

        skip(1);
        // way decreased but still > 1, par increases
        vox.poke();
        assertGt(vat.par(), expectedpar3);
        skip(1);
        // way ~= 1, par shouldn't change much
        vox.poke();
        assertGt(vat.par(), expectedpar3);
        skip(1);
        // way < 1, should decrease, maybe rounding error goes a little under par3
        vox.poke();
        assertLe(vat.par(), expectedpar3);
        skip(1);
        // way < 1, should decrease
        vox.poke();
        assertLe(vat.par(), expectedpar2);

        feed.push(rtag, bytes32(0), 10 ** 12);
        skip(100000000);
        // way doesn't change until after par update
        vox.poke();
        skip(100000000);
        vox.poke();
        assertGe(vat.par(), 20 * WAD);
    }
}

