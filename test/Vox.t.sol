// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.25;

import "forge-std/Test.sol";

import { RicoSetUp } from "./RicoHelper.sol";
import { File } from '../src/file.sol';
import { Vat } from '../src/vat.sol';
import { Vox } from '../src/vox.sol';

contract VoxTest is Test, RicoSetUp {
    uint pre_cap;
    uint constant init_par = 7 * RAY;

    modifier _orig_ {
        File(bank).file(bytes32('cap'), bytes32(pre_cap));
        _;
    }

    function setUp() public {
        make_bank();

        pre_cap = Vox(bank).cap();
        File(bank).file('tip.tag', rutag);
        File(bank).file('cap', bytes32(File(bank).CAP_MAX()));
        File(bank).file('par', bytes32(init_par));
    }

    function test_sway() public {
        // hardcoding way; price shouldn't matter
        feedpush(rutag, bytes32(UINT256_MAX / RAY), block.timestamp + 1000);

        // way == 1 -> poke shouldn't change par
        skip(100);
        Vox(bank).poke();
        assertEq(Vat(bank).par(), init_par);

        // way == 2 -> par should 10X every year
        File(bank).file(bytes32('way'), bytes32(File(bank).CAP_MAX()));
        skip(2 * BANKYEAR);
        Vox(bank).poke();
        assertClose(Vat(bank).par(), init_par * 100, 1_000_000_000);
    }

    function test_poke_basic_highmar() public
    {
        skip(1);
        uint way = Vox(bank).way();

        // mar > par -> poke should lower way
        feedpush(rutag, bytes32(init_par * 10 / 7), block.timestamp + 1000);
        Vox(bank).poke();
        assertLt(Vox(bank).way(), way);
    }

    function test_poke_lowmar_gas() public {
        skip(1);
        uint way = Vox(bank).way();

        // mar < par -> poke should raise way
        feedpush(rutag, bytes32(init_par / 2), block.timestamp + 1000);
        Vox(bank).poke();
        assertGt(Vox(bank).way(), way);
    }

    function test_ricolike_vox() public
    {
        // how > 0 and mar < par
        uint how = RAY + (RAY * 12 / 10) / (10 ** 16);
        File(bank).file(bytes32('how'), bytes32(how));
        feedpush(rutag, bytes32(0), 10 ** 12);

        // no time has passed -> par and way unchanged
        Vox(bank).poke();
        assertEq(Vat(bank).par(), 7 * RAY);
        assertEq(Vox(bank).way(), RAY);

        // time has passed, but way changes after par change
        // -> par still unchanged, way *= how
        skip(1);
        Vox(bank).poke();
        uint expectedpar = init_par;
        assertEq(Vat(bank).par(), expectedpar);
        uint expectedway = how;
        assertEq(Vox(bank).way(), expectedway);

        // way > 1 -> par rises
        skip(1);
        Vox(bank).poke();
        assertEq(Vat(bank).par(), expectedpar = rmul(expectedpar, expectedway));
        assertEq(Vox(bank).way(), expectedway = rmul(expectedway, how));

        // way rose again last poke -> par increases more this time
        // mar > par this time -> way decreases
        skip(1);
        feedpush(rutag, bytes32(10 * RAY), 10 ** 12);
        Vox(bank).poke();
        assertEq(Vat(bank).par(), expectedpar = rmul(expectedpar, expectedway));
        assertEq(Vox(bank).way(), expectedway = rdiv(expectedway, how));

        // way decreased but still > 1 -> par increases
        // mar > par -> way decreases
        skip(1);
        Vox(bank).poke();
        assertEq(Vat(bank).par(), expectedpar = rmul(expectedpar, expectedway));
        assertEq(Vox(bank).way(), expectedway = rmul(expectedway, rinv(how)));

        // way ~= 1, par shouldn't change much
        skip(1);
        Vox(bank).poke();
        assertClose(Vat(bank).par(), expectedpar, RAY / 10);
        assertEq(Vat(bank).par(), expectedpar = rmul(expectedpar, expectedway));
        assertEq(Vox(bank).way(), expectedway = rmul(expectedway, rinv(how)));

        // way < 1, par should decrease
        skip(1);
        Vox(bank).poke();
        assertLt(Vat(bank).par(), expectedpar);
        assertEq(Vat(bank).par(), expectedpar = rmul(expectedpar, expectedway));
        assertEq(Vox(bank).way(), expectedway = rmul(expectedway, rinv(how)));

        // way < 1, par should decrease
        skip(1);
        Vox(bank).poke();
        assertLt(Vat(bank).par(), expectedpar);
        assertEq(Vat(bank).par(), expectedpar = rmul(expectedpar, expectedway));
        assertEq(Vox(bank).way(), expectedway = rmul(expectedway, rinv(how)));

        // mar < par -> way should start increasing again
        feedpush(rutag, bytes32(0), 10 ** 12);

        // way doesn't change until after par update
        skip(100000000);
        Vox(bank).poke();
        skip(100000000);
        Vox(bank).poke();
        assertGe(Vat(bank).par(), init_par * 3);
    }

    function test_ttl() public {
        uint old_way = Vox(bank).way();
        vm.startPrank(Vox(bank).tip().src);

        // push an expired mar
        File(bank).fb().push(Vox(bank).tip().tag, bytes32(Vat(bank).par()), block.timestamp - 1);

        vm.stopPrank();

        // feed expired -> way shouldn't change
        Vox(bank).poke();
        assertEq(old_way, Vox(bank).way());
    }

    function test_cap_min() public _orig_ {
        // _orig_ set cap back to original value, otw it's too big to quickly reach
        Vox(bank).poke();
        skip(100000000);

        // push mar << par
        vm.startPrank(Vox(bank).tip().src);
        File(bank).fb().push(Vox(bank).tip().tag, 0, block.timestamp + 1);
        vm.stopPrank();

        // accumulates the skipped mar changes as if mar < par the whole time
        // -> way should hit cap
        Vox(bank).poke();
        assertEq(Vox(bank).way(), Vox(bank).cap());
        assertEq(Vat(bank).par(), init_par);
    }

    function test_cap_max() public _orig_ {
        // _orig_ set cap back to original value, otw it's too big to quickly reach
        Vox(bank).poke();
        assertEq(Vat(bank).par(), init_par);

        skip(100000000);

        // poke mar >> par
        vm.startPrank(Vox(bank).tip().src);
        uint256 high = 2 ** 128;
        File(bank).fb().push(Vox(bank).tip().tag, bytes32(high), block.timestamp + 1 );
        vm.stopPrank();

        // waited a long time to poke -> way should hit cap
        Vox(bank).poke();
        assertEq(Vox(bank).way(), rinv(Vox(bank).cap()));
    }

    function test_par_grows_with_stale_tip() public _orig_ {
        // set rico market feed low and fresh
        feedpush(rutag, bytes32(RAY), block.timestamp + 10000);
        skip(10);
        Vox(bank).poke();

        uint way0 = Vox(bank).way();
        uint par0 = Vat(bank).par();

        // set rico market feed low and stale
        feedpush(rutag, bytes32(RAY), block.timestamp);
        skip(10);
        Vox(bank).poke();

        // without market price sense par should progress but not way
        uint way1 = Vox(bank).way();
        uint par1 = Vat(bank).par();
        assertEq(way1, way0);
        assertGt(par1, par0);

        // set rico market feed low and fresh, without progressing time
        feedpush(rutag, bytes32(RAY), block.timestamp + 10000);
        Vox(bank).poke();

        // no delayed way change after feed refreshed
        uint way2 = Vox(bank).way();
        uint par2 = Vat(bank).par();
        assertEq(way2, way1);
        assertEq(par2, par1);

        // with fresh rico market feed both should progress
        feedpush(rutag, bytes32(RAY), block.timestamp + 10000);
        skip(10);
        Vox(bank).poke();

        uint way3 = Vox(bank).way();
        uint par3 = Vat(bank).par();
        assertGt(way3, way2);
        assertGt(par3, par2);
    }

    // Sanity test that release constants behave as expected
    function test_release_how_day() public _orig_ {
        Vox(bank).poke();
        uint par0 = Vat(bank).par();
        uint way0 = Vox(bank).way();
        assertEq(way0, RAY);

        // wait a std day and poke with market price below par
        feedpush(rutag, bytes32(0), block.timestamp + 10 * BANKYEAR);
        skip(1 days);
        Vox(bank).poke();

        // wait a bank year and poke again to see the way par changes
        skip(BANKYEAR);
        Vox(bank).poke();

        uint par1 = Vat(bank).par();
        uint incr = rdiv(par1, par0);

        // given const of 1000000000000003652500000000, how way changed should
        // have increased par by 1% over 365.25 days (BANKYEAR)
        assertClose(incr, RAY * 101 / 100, 100000);
    }

    // test how long it takes for way to reach cap
    function test_release_how_cap_up() public _orig_ {
        // no time passed, way unchanged
        Vox(bank).poke();
        uint way0 = Vox(bank).way();
        assertEq(way0, RAY);

        // set mar << par
        feedpush(rutag, bytes32(0), block.timestamp + 10 * BANKYEAR);
        skip(68.9 days);
        Vox(bank).poke();

        assertLt(Vox(bank).way(), Vox(bank).cap());

        skip(1 days);
        Vox(bank).poke();

        // with single direction movement way should take 69 days
        // to go from neutral to cap
        assertEq(Vox(bank).way(), Vox(bank).cap());
    }

    // same as test_release_how_cap_up, except way decreasing
    function test_release_how_cap_down() public _orig_ {
        Vox(bank).poke();
        uint way0 = Vox(bank).way();
        assertEq(way0, RAY);

        // set mar >> par
        feedpush(rutag, bytes32(1_000_000_000 * RAY), block.timestamp + 10 * BANKYEAR);
        skip(68.9 days);
        Vox(bank).poke();

        assertGt(Vox(bank).way(), rinv(Vox(bank).cap()));

        skip(1 days);
        Vox(bank).poke();

        // with single direction movement way should take 69 days
        // to go from neutral to cap
        assertEq(Vox(bank).way(), rinv(Vox(bank).cap()));
    }

    // test par movement while at cap
    function test_release_cap_up() public _orig_ {
        // Let way grow to cap
        Vox(bank).poke();
        feedpush(rutag, bytes32(0), block.timestamp + 10 * BANKYEAR);
        skip(100 days);
        Vox(bank).poke();

        // let par grow for a year at max way
        uint par0 = Vat(bank).par();
        skip(BANKYEAR);
        Vox(bank).poke();
        uint par1 = Vat(bank).par();
        uint incr = rdiv(par1, par0);

        // at max growth par should should double in one year
        assertClose(incr, RAY * 2, 1_000);
    }

    // same as test_release_cap_up, except way is at lower bound
    function test_release_cap_down() public _orig_ {
        // Let way grow to inv cap
        Vox(bank).poke();
        feedpush(rutag, bytes32(1_000_000_000 * RAY), block.timestamp + 10 * BANKYEAR);
        skip(100 days);
        Vox(bank).poke();

        // let par grow for a year at min way
        uint par0 = Vat(bank).par();
        skip(BANKYEAR);
        Vox(bank).poke();
        uint par1 = Vat(bank).par();
        uint incr = rdiv(par1, par0);

        // should halve
        assertClose(incr, RAY / 2, 1_000);
    }

    // test that way changes at expected rate before reaching cap
    function test_release_how_day_down() public _orig_ {
        Vox(bank).poke();
        uint par0 = Vat(bank).par();
        uint way0 = Vox(bank).way();
        assertEq(way0, RAY);

        // wait a std day and poke with market price above par
        feedpush(rutag, bytes32(1_000_000_000 * RAY), block.timestamp + 10 * BANKYEAR);
        skip(1 days);
        Vox(bank).poke();

        // wait a bank year and poke again to see the way par changes
        skip(BANKYEAR);
        Vox(bank).poke();

        uint par1 = Vat(bank).par();
        uint incr = rdiv(par1, par0);

        // given const of 1000000000000003652500000000, how way changed should
        // have decreased par by 1% over 365.25 days (BANKYEAR)
        assertClose(incr, RAY * 100 / 101, 100000);
    }

    function test_tick_down_on_deficit() public _orig_ {
        // mar < par, but deficit
        force_fees(WAD);
        force_sin(Vat(bank).joy() * RAY + RAD);
        feedpush(rutag, 0, UINT256_MAX);

        skip(100);
        uint way0 = Vox(bank).way();
        Vox(bank).poke();
        assertLt(Vox(bank).way(), way0);

        skip(100);
        force_sin((Vat(bank).joy() + 1) * RAY);
        way0 = Vox(bank).way();
        Vox(bank).poke();
        assertLt(Vox(bank).way(), way0);

        skip(100);
        force_sin(Vat(bank).joy() * RAY);
        way0 = Vox(bank).way();
        Vox(bank).poke();
        assertGt(Vox(bank).way(), way0);
    }

}
