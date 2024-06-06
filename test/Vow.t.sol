// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.25;

import "forge-std/Test.sol";

import { Vat, Vow, File, Bank, RicoSetUp } from "./RicoHelper.sol";
import { Guy } from "./RicoHelper.sol";
import { Ball, Gem } from "./RicoHelper.sol";
import { Math } from '../src/mixin/math.sol';

// integrated vow/flow tests
contract VowTest is Test, RicoSetUp {
    uint256   init_join = 1000;
    uint      stack = WAD * 10;
    bytes32[] ilks;
    uint      back_count;

    function setUp() public
    {
        make_bank();
        init_risk();
        ilks.push(rilk);

        // have 10k each of rico, risk and risk
        risk.approve(bank, type(uint256).max);

        // mint some rico and risk for hysteresis
        rico_mint(2000 * WAD, true);
        rico.transfer(address(1), rico.balanceOf(self));
        risk.mint(self, 100000 * WAD);

        // non-self user
        guy = new Guy(bank);
    }

    function test_flap_price() public
    {
        uint borrow = WAD;

        // risk:rico price 0.1
        uint rico_price_in_risk = 10;

        Vat(bank).frob(rilk, self, int(WAD), int(borrow));

        // accumulate a bunch of fees
        skip(BANKYEAR);
        Vat(bank).drip(rilk);

        // joy depends on tart and change in rack
        uint surplus = Vat(bank).joy();
        uint rack    = Vat(bank).ilks(rilk).rack;
        assertClose(surplus, rmul(rack, borrow) - borrow, 1_000_000_000);

        // cancel out any sin so only joy needs to be considered
        uint sin_wad = Vat(bank).sin() / RAY;
        force_fees(sin_wad);

        uint expected_risk_cost = surplus * rico_price_in_risk;

        // do the surplus auction
        risk.mint(self, WAD * 1_000);
        uint self_rico_1 = rico.balanceOf(self);
        uint self_risk_1 = risk.balanceOf(self);

        // set dam and bel so it just takes one second to reach target price
        uint dam = rmul(rinv(Vow(bank).pex()), rico_price_in_risk * RAY);
        file('dam', bytes32(dam));
        file('bel', bytes32(block.timestamp));
        skip(1);

        Vow(bank).keep(empty);

        uint rico_gain = rico.balanceOf(self) - self_rico_1;
        uint risk_cost = self_risk_1 - risk.balanceOf(self);

        // earn should depend on price
        assertClose(expected_risk_cost, risk_cost, 10_000);
        assertEq(rico_gain, surplus);
    }

    function test_basic_keep_deficit() public
    {
        Vat(bank).frob(rilk, self, int(WAD), int(WAD));

        // bail creates some sin
        Vat(bank).filk(rilk, 'fee', bytes32(FEE_2X_ANN));
        skip(BANKYEAR * 2);
        Vat(bank).bail(rilk, self);

        // create some rico to pay for the flop
        rico_mint(1000 * WAD, false);

        // add on a couple ilks so keep does more than one loop iteration
        skip(1);
        bytes32[] memory rilks = new bytes32[](2);
        rilks[0] = rilk; rilks[1] = rilk;
        Vow(bank).keep(rilks);
        assertGt(Vat(bank).sin() / RAY, Vat(bank).joy());
    }

    function test_basic_keep_surplus() public
    {
        risk.mint(self, 3000 * WAD);
        // set fee > 1 so rack changes
        Vat(bank).filk(rilk, 'fee', bytes32(FEE_2X_ANN));
        file('wel', bytes32(RAY / 2));
        file('bel', bytes32(block.timestamp - 1));
        file('dam', bytes32(RAY / WAD));

        Vat(bank).frob(rilk, self, int(WAD * 3000), int(WAD * 3000));

        skip(BANKYEAR);

        // add on a couple ilks so keep does more than one loop iteration
        bytes32[] memory rilks = new bytes32[](2);
        rilks[0] = rilk; rilks[1] = rilk;
        Vow(bank).keep(rilks);
        assertGt(Vat(bank).joy(), Vat(bank).sin() / RAY);
    }

    function test_drip_1() public
    {
        // should be 0 pending fees
        uint rho = Vat(bank).ilks(rilk).rho;
        assertEq(rho, block.timestamp);
        assertEq(rico.balanceOf(self), 0);

        // set high fee, risk:ref price 1k
        Vat(bank).filk(rilk, 'fee', bytes32(FEE_2X_ANN));
        Vat(bank).frob(rilk, address(this), int(WAD), int(WAD));

        // wipe previous frob
        uint firstrico = rico.balanceOf(self);
        rico_mint(1, false); // vat burns 1 extra to round in system's favor
        Vat(bank).frob(rilk, address(this), -int(WAD), -int(WAD));

        skip(BANKYEAR);

        // test rack, frob auto drips so same dart should draw double after a year at 2X fee
        Vat(bank).frob(rilk, address(this), int(WAD * 2), int(WAD));
        assertClose(rico.balanceOf(self), firstrico * 2, 1_000_000);

        rico_mint(1, false); // rounding
        Vat(bank).frob(rilk, address(this), -int(WAD), -int(WAD));
    }

    function test_keep_balanced() public
    {
        force_fees(Vat(bank).sin() / RAY);
        Vow(bank).keep(empty);

        // budget balanced; shouldn't do anything, not even heal
        assertGt(Vat(bank).joy(), 1);
        assertEq(Vat(bank).joy(), Vat(bank).sin() / RAY);
    }

    function test_keep_unbalanced_slightly_more_rico() public
    {
        // set fee == 2 so easy to predict djoy
        Vat(bank).filk(rilk, 'fee', bytes32(FEE_2X_ANN));

        // frob enough rico to cover sin later, plus a lil extra
        uint amt = Vat(bank).sin() / RAY + 1;
        rico_mint(amt, false);

        // djoy after 1y will be just over amt
        skip(BANKYEAR);

        // set dam and bel so it just takes one second to reach target price
        file('dam', bytes32(rinv(Vow(bank).pex())));
        file('bel', bytes32(block.timestamp));
        skip(1);

        assertEq(Vat(bank).joy(), 0);
        uint self_risk_1 = risk.balanceOf(self);
        Vow(bank).keep(single(rilk));
        uint self_risk_2 = risk.balanceOf(self);

        // unlike test_keep_balanced, budget was not balanced
        // -> keep healed
        assertEq(Vat(bank).joy(), 1);
        assertGt(self_risk_1, self_risk_2);
    }

    function test_zero_flap() public
    {
        // joy > sin, but joy too small to flap
        force_sin(0);
        force_fees(1);
        Vow(bank).keep(empty);

        assertEq(Vat(bank).sin(), 0);
        assertEq(Vat(bank).joy(), 1);

        // vow leaves at least 1 joy to avoid toggling 0
        // so this keep should flap 0
        uint pre_rico = rico.balanceOf(self);
        uint pre_risk = risk.balanceOf(self);
        Vow(bank).keep(empty);
        uint aft_rico = rico.balanceOf(self);
        uint aft_risk = risk.balanceOf(self);

        assertEq(aft_rico, pre_rico);
        assertEq(aft_risk, pre_risk);
    }

    function test_wel() public _check_integrity_after_
    {
        // can't flap more rico than surplus
        vm.expectRevert(Bank.ErrBound.selector);
        new Vow(Bank.BankParams(arico, arisk), Vow.VowParams(RAY + 1, RAY, RAY, 0, 0));

        uint wel = RAY / 7;
        file('wel', bytes32(wel));
        Vat(bank).frob(rilk, self, int(WAD), int(WAD));

        // drip a bunch of joy
        Vat(bank).filk(rilk, 'fee', bytes32(Vat(bank).FEE_MAX()));
        skip(5 * BANKYEAR);
        Vat(bank).drip(rilk);

        // keep should flap 1/7 the joy
        uint joy = Vat(bank).joy() - Vat(bank).sin() / RAY;
        uint pre_rico = rico.balanceOf(self);
        uint pre_risk = risk.balanceOf(self);

        // set dam and bel so it just takes one second to reach target price
        file('dam', bytes32(rinv(Vow(bank).pex())));
        file('bel', bytes32(block.timestamp - 1));
        file('wal', bytes32(RAD));
        Vow(bank).keep(empty);

        uint aft_rico = rico.balanceOf(self);
        uint aft_risk = risk.balanceOf(self);

        assertClose(aft_rico - pre_rico, rmul(joy, wel), 100000000000);

        uint act_price = rdiv(pre_risk - aft_risk, aft_rico - pre_rico);
        assertClose(act_price, RAY, 1000000);
    }

    function test_dam() public {
        risk.mint(self, UINT256_MAX - risk.totalSupply());
        file('bel', bytes32(block.timestamp));
        file('wel', bytes32(RAY));
        file('wal', bytes32(RAD));
        file('dam', bytes32(RAY / 10));

        // no time elapsed, price == pex
        force_fees(Vat(bank).sin() / RAY + WAD);
        uint prerisk = risk.balanceOf(self);
        Vow(bank).keep(empty);

        assertClose(prerisk - risk.balanceOf(self), rmul(WAD, Vow(bank).pex()), BLN);

        // 1s elapsed, price == pex / 10
        skip(1);
        force_fees(Vat(bank).sin() / RAY + WAD);
        prerisk = risk.balanceOf(self);
        Vow(bank).keep(empty);

        assertClose(prerisk - risk.balanceOf(self), rmul(WAD, Vow(bank).pex()) / 10, BLN);

        // 4s elapsed, price == pex / 10000
        skip(4);
        force_fees(Vat(bank).sin() / RAY + WAD);
        prerisk = risk.balanceOf(self);
        Vow(bank).keep(empty);

        assertClose(
            prerisk - risk.balanceOf(self), rmul(WAD, Vow(bank).pex()) / 10000, BLN
        );

        // lots of time elapsed, dam lowers price to 0
        skip(BANKYEAR);
        force_fees(Vat(bank).sin() / RAY + WAD);
        prerisk = risk.balanceOf(self);
        Vow(bank).keep(empty);
        assertEq(prerisk - risk.balanceOf(self), 0);
    }

    function test_keep_noop_on_deficit() public {
        force_fees(WAD);
        force_sin(Vat(bank).joy() * RAY + RAD);

        uint deficit = Vat(bank).sin() / RAY - Vat(bank).joy();
        Vow(bank).keep(empty);

        assertEq(Vat(bank).sin() / RAY - Vat(bank).joy(), deficit);
    }

    function test_mine() public {
        file('mop', bytes32(uint(999999978035500000000000000)));
        assertEq(Vow(bank).phi(), block.timestamp);
        uint prerisk = risk.totalSupply();
        uint lax = Vow(bank).lax();
        uint mop = Vow(bank).mop();

        Vow(bank).mine();
        assertEq(risk.totalSupply(), prerisk);
        assertEq(Vow(bank).phi(), block.timestamp);

        skip(1);
        uint pregif = Vow(bank).gif();
        uint flate = rmul(Vow(bank).wal(), lax);
        Vow(bank).mine();
        assertEq(risk.totalSupply(), prerisk + Vow(bank).gif() + flate);
        assertEq(Vow(bank).gif(), rmul(pregif, mop));
        assertEq(Vow(bank).phi(), block.timestamp);

        skip(BANKYEAR);
        prerisk = risk.totalSupply();
        pregif = Vow(bank).gif();
        flate = rmul(Vow(bank).wal(), lax);
        Vow(bank).mine();
        assertEq(risk.totalSupply(), prerisk + (Vow(bank).gif() + flate) * BANKYEAR);
        assertClose(Vow(bank).gif(), pregif / 2, 1000000);
        assertEq(Vow(bank).phi(), block.timestamp);

        prerisk = risk.totalSupply();
        pregif  = Vow(bank).gif();
        Vow(bank).mine();
        assertEq(risk.totalSupply(), prerisk);
        assertEq(Vow(bank).phi(), block.timestamp);

        assertEq(risk.totalSupply(), risk.balanceOf(self));
    }

    function test_gif() public {
        file('mop', bytes32(RAY));
        file('lax', 0);
        file('gif', bytes32(WAD * 3));

        skip(BANKYEAR);
        uint prerisk = risk.totalSupply();
        Vow(bank).mine();
        assertEq(risk.totalSupply(), prerisk + WAD * 3 * BANKYEAR);

        skip(10);
        file('gif', 0);
        prerisk = risk.totalSupply();
        Vow(bank).mine();
        assertEq(risk.totalSupply(), prerisk);
    }

    function test_mop() public {
        file('gif', bytes32(WAD));
        file('mop', 0);
        file('lax', 0);

        skip(1);
        uint prerisk = risk.totalSupply();
        Vow(bank).mine();
        assertEq(risk.totalSupply(), prerisk);
        assertEq(Vow(bank).gif(), 0);

        skip(1000);
        prerisk = risk.totalSupply();
        Vow(bank).mine();
        assertEq(risk.totalSupply(), prerisk);
        assertEq(Vow(bank).gif(), 0);

        file('gif', bytes32(WAD));
        file('mop', bytes32(RAY / 2));
        skip(2);
        prerisk = risk.totalSupply();
        Vow(bank).mine();
        assertEq(risk.totalSupply(), prerisk + WAD / 4 * 2);
        assertEq(Vow(bank).gif(), WAD / 4);
    }

    function test_lax() public {
        file('gif', bytes32(WAD));
        file('mop', bytes32(RAY));
        file('lax', 0);

        skip(1);
        uint prerisk = risk.totalSupply();
        Vow(bank).mine();
        assertEq(risk.totalSupply(), prerisk + WAD);

        skip(1);
        prerisk = risk.totalSupply();
        uint prewal = Vow(bank).wal();
        uint lax = RAY / 10000000000;
        file('lax', bytes32(lax));
        Vow(bank).mine();
        assertEq(risk.totalSupply(), prerisk + WAD + rmul(lax, prewal));

        skip(1);
        prewal = Vow(bank).wal();
        prerisk = risk.totalSupply();
        file('lax', bytes32(lax));
        Vow(bank).mine();
        assertEq(risk.totalSupply(), prerisk + WAD + rmul(lax, prewal));

        file('mop', 0);
        skip(BANKYEAR);
        prewal = Vow(bank).wal();
        prerisk = risk.totalSupply();
        Vow(bank).mine();
        assertEq(risk.totalSupply(), prerisk + rmul(lax, prewal) * BANKYEAR);
    }

    function test_keep_wal() public {
        force_fees(Vat(bank).sin() / RAY + 1000 * WAD);
        set_dxm('dam', RAY);

        // keep creates equal changes in risk supply and wal
        uint prewal = Vow(bank).wal();
        uint prerisk = risk.totalSupply();
        Vow(bank).keep(empty);
        assertFalse(prewal == Vow(bank).wal());
        assertFalse(prerisk == risk.totalSupply());
        assertEq(prewal - Vow(bank).wal(), prerisk - risk.totalSupply());

        skip(1000);

        // so does mine
        prewal = Vow(bank).wal();
        prerisk = risk.totalSupply();
        Vow(bank).mine();
        assertFalse(prewal == Vow(bank).wal());
        assertFalse(prerisk == risk.totalSupply());
        assertEq(Vow(bank).wal() - prewal, risk.totalSupply() - prerisk);
    }

}

contract VowJsTest is Test, RicoSetUp {
    // me == js ALI
    address me;
    Guy bob;
    Guy cat;
    address b;
    address c;

    function setUp() public
    {
        make_bank();
        init_risk();

        me = address(this);
        bob = new Guy(bank);
        cat = new Guy(bank);
        b = address(bob);
        c = address(cat);

        risk.mint(me, 16000 * WAD);
        risk.approve(bank, UINT256_MAX);

        Vat(bank).filk(rilk, 'line', bytes32(10000 * RAD));
        Vat(bank).filk(rilk, 'chop', bytes32(RAY * 11 / 10));

        // fee == 5%/yr == ray(1.05 ** (1/BANKYEAR))
        uint fee = 1000000001546067052200000000;
        Vat(bank).filk(rilk, 'fee', bytes32(fee));
        Vat(bank).frob(rilk, me, int(100 * WAD), 0);
        Vat(bank).frob(rilk, me, int(0), int(99 * WAD));

        // cat frobs some rico and transfers to me
        risk.mint(c, 7000 * WAD);
        cat.approve(arisk, bank, UINT256_MAX);
        cat.frob(rilk, c, int(4001 * WAD), int(4000 * WAD));
        cat.transfer(arico, me, 4000 * WAD);

        // used to setup uni pools here, no more though
        // transfer the rico to 1 instead so balances/supplies are same
        rico.transfer(address(1), 4000 * WAD);
        risk.transfer(address(1), 2000 * WAD);

        file('bel', bytes32(block.timestamp));

        guy = new Guy(bank);
    }

    function test_init_conditions() public view
    {
        // frobbed the rico and no time has passed, so should be safe
        assertEq(rico.balanceOf(me), 99 * WAD);
        (uint deal,) = Vat(bank).safe(rilk, me);
        assertEq(deal, RAY);
    }

    function test_bail_urns_1yr_unsafe() public
    {
        // wait a year, flap the surplus
        skip(BANKYEAR);

        // risk:rico price 1
        set_dxm('dam', RAY);
        Vow(bank).keep(single(rilk));

        (uint deal,) = Vat(bank).safe(rilk, me);
        assertLt(deal, RAY);

        // should be balanced (enough)
        assertEq(Vat(bank).sin(), 0);
        assertEq(Vat(bank).joy(), 1);

        // bail the urn frobbed in setup
        assertGt(_ink(rilk, me), 0);
        Vat(bank).bail(rilk, me);

        // urn should be bailed, excess ink should be sent back to urn holder
        uint ink = _ink(rilk, me); uint art = _art(rilk, me);
        assertEq(art, 0);
        assertEq(ink, 0);

        // more joy and more sin
        uint joy = Vat(bank).joy();
        uint sin = Vat(bank).sin();
        assertGt(sin / RAY, joy);
        assertGt(joy, 1);
    }

    function test_bail_urns_when_safe() public
    {
        // can't bail a safe urn
        vm.expectRevert(Vat.ErrSafeBail.selector);
        Vat(bank).bail(rilk, me);

        uint sin0 = Vat(bank).sin();
        assertEq(sin0 / RAY, 0);

        skip(BANKYEAR);

        // it's unsafe now; can bail
        Vat(bank).bail(rilk, me);

        // was just bailed, so now it's safe
        vm.expectRevert(Vat.ErrSafeBail.selector);
        Vat(bank).bail(rilk, me);
    }

    function test_keep_vow_1yr_drip_flap() public
    {
        // wait a year to drip 5%
        uint initial_total = rico.totalSupply();
        skip(BANKYEAR);

        // risk:rico price 1
        set_dxm('dam', RAY);

        // should flap
        Vow(bank).keep(single(rilk));

        // minted 4099, fee is 1.05. 0.05*4099 as no surplus buffer
        uint final_total = rico.totalSupply();
        assertGe(final_total - initial_total, 204.94e18);
        assertLe(final_total - initial_total, 204.96e18);
    }

    function test_e2e_all_actions() public
    {
        // run a flap and ensure risk is burnt
        // pep a little bit more to account for chop >1 now that liqr is in hook
        Vat(bank).filk(rilk, 'pep', bytes32(uint(3)));
        uint risk_initial_supply = risk.totalSupply();
        skip(BANKYEAR);

        risk.mint(address(guy), 1000 * WAD);

        set_dxm('dam', RAY / 2);
        guy.keep(single(rilk));

        uint risk_post_flap_supply = risk.totalSupply();
        assertLt(risk_post_flap_supply, risk_initial_supply + 1000 * WAD * 2);

        // confirm bail trades the risk for rico
        uint joy0 = Vat(bank).joy();
        Vat(bank).bail(rilk, me);
        uint joy1 = Vat(bank).joy();
        assertGt(joy1, joy0);
    }

}
