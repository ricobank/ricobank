// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import { RicoSetUp } from "./RicoHelper.sol";
import { File } from '../src/file.sol';
import { Vat } from '../src/vat.sol';
import { Vox } from '../src/vox.sol';

contract VoxTest is Test, RicoSetUp {
    uint256 public init_join = 1000;
    uint stack = WAD * 10;
    bytes32[] ilks;
    bytes32 pool_id_rico_risk;
    bytes32 pool_id_gold_rico;

    function setUp() public {
        make_bank();
        File(bank).file(bytes32('tag'), rtag);
        File(bank).file(bytes32('cap'), bytes32(3 * RAY));
        File(bank).file('par', bytes32(7 * WAD));
    }

    function test_sway() public {
        feedpush(rtag, bytes32(7 * WAD), block.timestamp + 1000);

        skip(100);
        Vox(bank).poke();
        assertEq(Vat(bank).par(), 7 * WAD);

        File(bank).file(bytes32('way'), bytes32(2 * RAY));
        skip(2);
        Vox(bank).poke();
        assertEq(Vat(bank).par(), 28 * WAD);
    }

    function test_poke_highmar_gas() public {
        skip(1);
        uint way = Vox(bank).way();
        feedpush(rtag, bytes32(10 * WAD), block.timestamp + 1000);
        uint gas = gasleft();
        Vox(bank).poke();
        check_gas(gas, 30043);
        assertLt(Vox(bank).way(), way);
    }

    function test_poke_lowmar_gas() public {
        skip(1);
        uint way = Vox(bank).way();
        feedpush(rtag, bytes32(1 * WAD / (Vox(bank).amp() / RAY)), block.timestamp + 1000);
        uint gas = gasleft();
        Vox(bank).poke();
        check_gas(gas, 29556);
        assertGt(Vox(bank).way(), way);
    }

    function test_ricolike_vox() public {
        Vox(bank).poke(); // how > 1 but mar == par, par stuck at 7
        uint how = RAY + (RAY * 12 / 10) / (10 ** 16);
        File(bank).file(bytes32('how'), bytes32(how));
        feedpush(rtag, bytes32(Vox(bank).amp() / RAY), 10 ** 12);

        Vox(bank).poke(); // no time has passed
        assertEq(Vat(bank).par(), 7 * WAD);
        skip(1);
        Vox(bank).poke();
        assertEq(Vat(bank).par(), 7 * WAD); // way *= how, par will increase next

        skip(1);
        Vox(bank).poke();
        uint expectedpar2 = 7 * WAD * how / RAY;
        assertEq(Vat(bank).par(), expectedpar2); // way > 1 -> par increases

        skip(1);
        feedpush(rtag, bytes32(10 * WAD), 10 ** 12); // raise mar above par
        Vox(bank).poke(); // poke updates par before way, par should increase again
        // this time it's multiplied by how ** 2
        uint expectedpar3 = 7 * WAD * how / RAY * how / RAY * how / RAY;
        assertEq(Vat(bank).par(), expectedpar3);

        skip(1);
        // way decreased but still > 1, par increases
        Vox(bank).poke();
        assertGt(Vat(bank).par(), expectedpar3);
        skip(1);
        // way ~= 1, par shouldn't change much
        Vox(bank).poke();
        assertGt(Vat(bank).par(), expectedpar3);
        skip(1);
        // way < 1, should decrease, maybe rounding error goes a little under par3
        Vox(bank).poke();
        assertLe(Vat(bank).par(), expectedpar3);
        skip(1);
        // way < 1, should decrease
        Vox(bank).poke();
        assertLe(Vat(bank).par(), expectedpar2);

        feedpush(rtag, bytes32(0), 10 ** 12);
        skip(100000000);
        // way doesn't change until after par update
        Vox(bank).poke();
        skip(100000000);
        Vox(bank).poke();
        assertGe(Vat(bank).par(), 20 * WAD);
    }

    function test_ttl() public {
        uint old_way = Vox(bank).way();
        vm.startPrank(Vox(bank).tip());
        File(bank).fb().push(Vox(bank).tag(), bytes32(Vat(bank).par()), block.timestamp - 1);
        vm.stopPrank();
        Vox(bank).poke();
        assertEq(old_way, Vox(bank).way());
    }

    function test_cap_min() public {
        Vox(bank).poke();
        skip(100000000);
        vm.startPrank(Vox(bank).tip());
        File(bank).fb().push(Vox(bank).tag(), 0, block.timestamp + 1);
        vm.stopPrank();
        Vox(bank).poke();
        assertEq(Vox(bank).way(), Vox(bank).cap());
    }

    function test_cap_max() public {
        Vox(bank).poke();
        skip(100000000);
        vm.startPrank(Vox(bank).tip());
        uint256 high = 2 ** 128;
        File(bank).fb().push(Vox(bank).tag(), bytes32(high), block.timestamp + 1 );
        vm.stopPrank();
        Vox(bank).poke();
        assertEq(Vox(bank).way(), rinv(Vox(bank).cap()));
    }
}

