// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.25;

import "forge-std/Test.sol";

import { RicoSetUp } from "./RicoHelper.sol";
import { File } from '../src/file.sol';
import { Vat } from '../src/vat.sol';
import { Vox } from '../src/vox.sol';
import { Vow } from '../src/vow.sol';

contract VoxTest is Test, RicoSetUp {
    uint constant skip_period_low_mar  = 18 + 1;
    uint constant skip_period_high_mar = 18 - 1;
    uint constant init_par = 7 * RAY;
    uint pre_cap;
    bytes32[] ilks;
    uint way0;
    uint par0;
    enum MarLev {HIGH, LOW}

    modifier _orig_ {
        file(bytes32('cap'), bytes32(pre_cap));
        _;
    }

    function skip_and_keep(MarLev lev, uint dt) public {
        /* Temporarily modify dam to allow both waiting a long time and selecting poke direction.
        Calculating dam is difficult, just use limits and mint RISK. */

        uint orig_dam  = Vow(bank).dam();
        uint orig_risk = risk.balanceOf(self);

        if(lev == MarLev.HIGH) {
            file('dam', bytes32(RAY));
            risk.mint(self, type(uint256).max - risk.totalSupply());
        } else {
            file('dam', bytes32(0));
        }

        skip(dt);
        Vow(bank).keep(single(rilk));

        uint256 end_risk = risk.balanceOf(self);
        (end_risk > orig_risk) ? risk.burn(self, end_risk - orig_risk) : risk.mint(self, orig_risk - end_risk);

        file('dam', bytes32(orig_dam));
    }

    function setUp() public {
        make_bank();
        init_risk();
        ilks.push(rilk);
        risk.approve(bank, type(uint256).max);

        pre_cap = Vox(bank).cap();
        file('cap', bytes32(Vox(bank).CAP_MAX()));
        file('par', bytes32(init_par));
        file('dam', bytes32(RAY / 10));

        // accumulate surplus
        Vat(bank).frob(rilk, self, int(1000 * WAD), int(100 * WAD));
        skip(BANKYEAR);
        Vat(bank).drip(rilk);

        risk.mint(self, WAD * 1_000_000);
        way0 = Vox(bank).way();
        par0 = Vat(bank).par();

        // reset flap and poke timer
        file('bel', bytes32(block.timestamp));
    }

    function test_poke_sender() public {
        vm.expectRevert(Vox.ErrSender.selector);
        Vox(bank).poke(RAY, 0);
    }

    function test_decrease_way() public {
        // dam is set to 0.1 RAY, so waiting for about 18 seconds will cross price vs par
        skip(skip_period_high_mar);
        Vow(bank).keep(single(rilk));
        uint way1 = Vox(bank).way();

        // par of 7 means 1 RICO should have equal value to 7 RISK
        // waited for a short time so large price in RISK was paid for RICO, RICO was overpriced
        // so way should decrease as mar > par

        assertLt(way1, way0);
    }

    function test_increase_way() public {
        // dam is set to 0.1 RAY, so waiting for about 18 seconds will cross price vs par
        skip(skip_period_low_mar);
        Vow(bank).keep(single(rilk));
        uint way1 = Vox(bank).way();

        // par of 7 means 1 RICO should have equal value to 7 RISK
        // waited for a long time so small price in RISK was paid for RICO, RICO was underpriced
        // so way should increase as mar < par

        assertGt(way1, way0);
    }

    function test_tick_down_on_deficit() public _orig_ {
        // mar < par, but deficit
        force_fees(WAD);
        force_sin(Vat(bank).joy() * RAY + RAD);

        // dam is set to 0.1 RAY, so after about 18 seconds price will cross par
        skip(skip_period_low_mar);
        Vow(bank).keep(single(rilk));
        uint way1 = Vox(bank).way();

        // waited for over 18 seconds so mar would have been below par
        // but way should decrease as deficit should force it down
        assertLt(way1, way0);

        // repeating process with levelled sin should give opposite result
        skip(30);
        force_sin((Vat(bank).joy() + 1) * RAY);
        way0 = Vox(bank).way();

        Vow(bank).keep(single(rilk));
        assertGt(Vox(bank).way(), way0);
    }

    function test_sway() public {
        // hardcoding way; price shouldn't matter

        // way == 1 -> poke shouldn't change par
        skip(100);
        Vow(bank).keep(single(rilk));
        assertEq(Vat(bank).par(), init_par);

        // way == 2 -> par should 10X every year
        file(bytes32('way'), bytes32(Vox(bank).CAP_MAX()));
        skip(2 * BANKYEAR);
        Vow(bank).keep(single(rilk));
        assertClose(Vat(bank).par(), init_par * 100, 1_000_000_000);
    }

    function test_ricolike_vox() public
    {
        // how > 0 and mar < par
        uint how = RAY + (RAY * 12 / 10) / (10 ** 16);
        file(bytes32('how'), bytes32(how));

        // no more time has passed -> par and way unchanged
        risk.mint(self, Vow(bank).pex());
        Vow(bank).keep(single(rilk));
        assertEq(Vat(bank).par(), 7 * RAY);
        assertEq(Vox(bank).way(), RAY);

        // time has passed, but way changes after par change
        // -> par still unchanged, way *= how
        skip(skip_period_low_mar);
        Vow(bank).keep(single(rilk));
        uint expectedpar = init_par;
        assertEq(Vat(bank).par(), expectedpar);
        uint expectedway = grow(way0, how, skip_period_low_mar);
        assertEq(Vox(bank).way(), expectedway);

        // way > 1 -> par rises
        skip(skip_period_low_mar);
        Vow(bank).keep(single(rilk));
        assertEq(Vat(bank).par(), expectedpar = grow(expectedpar, expectedway, skip_period_low_mar));
        assertEq(Vox(bank).way(), expectedway = grow(expectedway, how, skip_period_low_mar));

        // way rose again last poke -> par increases more this time
        // mar > par this time -> way decreases
        skip(skip_period_high_mar);
        Vow(bank).keep(single(rilk));
        assertEq(Vat(bank).par(), expectedpar = grow(expectedpar, expectedway, skip_period_high_mar));
        assertEq(Vox(bank).way(), expectedway = grow(expectedway, rinv(how), skip_period_high_mar));

        // way decreased but still > 1 -> par increases
        // mar > par -> way decreases
        skip(skip_period_high_mar);
        Vow(bank).keep(single(rilk));
        assertEq(Vat(bank).par(), expectedpar = grow(expectedpar, expectedway, skip_period_high_mar));
        assertEq(Vox(bank).way(), expectedway = grow(expectedway, rinv(how), skip_period_high_mar));

        // repeat to cause way to drop below RAY
        skip(skip_period_high_mar);
        Vow(bank).keep(single(rilk));
        assertEq(Vat(bank).par(), expectedpar = grow(expectedpar, expectedway, skip_period_high_mar));
        assertEq(Vox(bank).way(), expectedway = grow(expectedway, rinv(how), skip_period_high_mar));

        // way < 1, par should decrease
        skip(skip_period_high_mar);
        Vow(bank).keep(single(rilk));
        assertLt(Vat(bank).par(), expectedpar);
        assertEq(Vat(bank).par(), expectedpar = grow(expectedpar, expectedway, skip_period_high_mar));
        assertEq(Vox(bank).way(), expectedway = grow(expectedway, rinv(how), skip_period_high_mar));

        // mar < par -> way should start increasing again
        skip(skip_period_low_mar);
        way0 = Vox(bank).way();
        Vow(bank).keep(single(rilk));
        uint way1 = Vox(bank).way();
        assertGe(way1, way0);
    }

    function test_cap_min() public _orig_ {
        // _orig_ set cap back to original value, otw it's too big to quickly reach
        // accumulates the skipped mar changes as if mar < par the whole time
        skip_and_keep(MarLev.LOW, 100000000);

        // -> way should hit cap
        assertEq(Vox(bank).way(), Vox(bank).cap());
        assertEq(Vat(bank).par(), init_par);
    }

    function test_cap_max() public _orig_ {
        // _orig_ set cap back to original value, otw it's too big to quickly reach
        // accumulates the skipped mar changes as if mar < par the whole time
        skip_and_keep(MarLev.HIGH, 100000000);
        assertEq(Vox(bank).way(), rinv(Vox(bank).cap()));
    }

    // Sanity test that release constants behave as expected
    function test_release_how_day() public _orig_ {
        way0 = Vox(bank).way();
        assertEq(way0, RAY);

        // wait a std day and poke with market price below par
        skip_and_keep(MarLev.LOW, 1 days);

        // wait a bank year and poke again to see the way par changes
        skip_and_keep(MarLev.LOW, BANKYEAR);

        uint par1 = Vat(bank).par();
        uint incr = rdiv(par1, par0);

        // given const of 1000000000000003652500000000, how way changed should
        // have increased par by 1% over 365.25 days (BANKYEAR)
        assertClose(incr, RAY * 101 / 100, 100000);
    }

    // test how long it takes for way to reach cap
    function test_release_how_cap_up() public _orig_ {
        // no time passed, way unchanged
        assertEq(way0, RAY);

        // set mar << par
        skip_and_keep(MarLev.LOW, 68.9 days);

        assertLt(Vox(bank).way(), Vox(bank).cap());

        skip_and_keep(MarLev.LOW, 1 days);

        // with single direction movement way should take 69 days
        // to go from neutral to cap
        assertEq(Vox(bank).way(), Vox(bank).cap());
    }

    // same as test_release_how_cap_up, except way decreasing
    function test_release_how_cap_down() public _orig_ {
        assertEq(way0, RAY);

        // set mar >> par
        skip_and_keep(MarLev.HIGH, 68.9 days);

        assertGt(Vox(bank).way(), rinv(Vox(bank).cap()));

        skip_and_keep(MarLev.HIGH, 1 days);

        // with single direction movement way should take 69 days
        // to go from neutral to cap
        assertEq(Vox(bank).way(), rinv(Vox(bank).cap()));
    }

    // test par movement while at cap
    function test_release_cap_up() public _orig_ {
        // Let way grow to cap
        skip_and_keep(MarLev.LOW, 100 days);

        // let par grow for a year at max way
        skip_and_keep(MarLev.LOW, BANKYEAR);
        uint par1 = Vat(bank).par();
        uint incr = rdiv(par1, par0);

        // at max growth par should should double in one year
        assertClose(incr, RAY * 2, 1_000);
    }

    // same as test_release_cap_up, except way is at lower bound
    function test_release_cap_down() public _orig_ {
        // Let way grow to inv cap
        skip_and_keep(MarLev.HIGH, 100 days);

        // let par grow for a year at min way
        skip_and_keep(MarLev.HIGH, BANKYEAR);
        uint par1 = Vat(bank).par();
        uint incr = rdiv(par1, par0);

        // should halve
        assertClose(incr, RAY / 2, 1_000);
    }

    // test that way changes at expected rate before reaching cap
    function test_release_how_day_down() public _orig_ {
        assertEq(way0, RAY);

        // wait a std day and poke with market price above par
        skip_and_keep(MarLev.HIGH, 1 days);

        // wait a bank year and poke again to see the way par changes
        skip_and_keep(MarLev.HIGH, BANKYEAR);

        uint par1 = Vat(bank).par();
        uint incr = rdiv(par1, par0);

        // given const of 1000000000000003652500000000, how way changed should
        // have decreased par by 1% over 365.25 days (BANKYEAR)
        assertClose(incr, RAY * 100 / 101, 100000);
    }
}
