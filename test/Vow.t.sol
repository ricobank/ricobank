// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.25;

import "forge-std/Test.sol";

import { Bank, RicoSetUp } from "./RicoHelper.sol";
import { Guy } from "./RicoHelper.sol";
import { Gem } from "./RicoHelper.sol";
import { Math } from '../src/mixin/math.sol';

// integrated vow/flow tests
contract VowTest is Test, RicoSetUp {
    uint256   init_join = 1000;
    uint      stack = WAD * 10;
    uint      back_count;

    function setUp() public
    {
        make_bank();

        // have 10k each of rico, risk and risk
        // mint some rico and risk for hysteresis
        rico_mint(2000 * WAD, true);
        rico.transfer(address(1), rico.balanceOf(self));
        risk_mint(self, 100000 * WAD);

        // non-self user
        guy = new Guy(bank);
    }

    function test_flap_price() public
    {
        uint borrow = WAD;

        // risk:rico price 0.1
        uint rico_price_in_risk = 10;

        bank.frob(self, int(WAD), int(borrow));

        // accumulate a bunch of fees
        skip(BANKYEAR);
        bank.frob(self, 0, 0);

        // joy depends on tart and change in rack
        uint surplus = bank.joy();
        uint rack    = bank.rack();
        assertClose(surplus, rmul(rack, borrow) - borrow, 1_000_000_000);

        // cancel out any sin so only joy needs to be considered
        uint sin_wad = bank.sin() / RAY;
        force_fees(sin_wad);

        uint expected_risk_cost = surplus * rico_price_in_risk;

        // do the surplus auction
        risk_mint(self, WAD * 1_000);
        uint self_rico_1 = rico.balanceOf(self);
        uint self_risk_1 = risk.balanceOf(self);

        // set dam and bel so it just takes one second to reach target price
        uint dam = rmul(rinv(bank.pex()), rico_price_in_risk * RAY);
        file('dam', bytes32(dam));
        file('bel', bytes32(block.timestamp));
        skip(1);

        uint pre_drip_joy = bank.joy();
        bank.frob(self, 0, 0);
        uint aft_drip_joy = bank.joy();
        surplus = surplus + aft_drip_joy - pre_drip_joy;

        bank.keep();

        uint rico_gain = rico.balanceOf(self) - self_rico_1;
        uint risk_cost = self_risk_1 - risk.balanceOf(self);

        // earn should depend on price
        assertClose(expected_risk_cost, risk_cost, 10_000);
        assertEq(rico_gain, surplus);
    }

    function test_basic_keep_deficit() public
    {
        bank.frob(self, int(WAD), int(WAD));

        // bail creates some sin
        file('fee', bytes32(FEE_2X_ANN));
        skip(BANKYEAR * 2);
        bank.bail(self);

        // create some rico to pay for the flop
        rico_mint(1000 * WAD, false);

        // add on a couple ilks so keep does more than one loop iteration
        skip(1);
        bank.keep();
        assertGt(bank.sin() / RAY, bank.joy());
    }

    function test_basic_keep_surplus() public
    {
        risk_mint(self, 3000 * WAD);
        // set fee > 1 so rack changes
        file('fee', bytes32(FEE_2X_ANN));
        file('wel', bytes32(RAY / 2));
        file('bel', bytes32(block.timestamp - 1));
        file('dam', bytes32(RAY / WAD));

        bank.frob(self, int(WAD * 3000), int(WAD * 3000));

        skip(BANKYEAR);

        bank.keep();
        assertGt(bank.joy(), bank.sin() / RAY);
    }

    function test_drip_1() public
    {
        // should be 0 pending fees
        uint rho = bank.rho();
        assertEq(rho, block.timestamp);
        assertEq(rico.balanceOf(self), 0);

        // set high fee, risk:ref price 1k
        file('fee', bytes32(FEE_2X_ANN));
        bank.frob(address(this), int(WAD), int(WAD));

        // wipe previous frob
        uint firstrico = rico.balanceOf(self);
        rico_mint(1, false); // vat burns 1 extra to round in system's favor
        bank.frob(address(this), -int(WAD), -int(WAD));

        skip(BANKYEAR);

        // test rack, frob auto drips so same dart should draw double after a year at 2X fee
        bank.frob(address(this), int(WAD * 2), int(WAD));
        assertClose(rico.balanceOf(self), firstrico * 2, 1_000_000);

        rico_mint(1, false); // rounding
        bank.frob(address(this), -int(WAD), -int(WAD));
    }

    function test_keep_balanced() public
    {
        force_fees(bank.sin() / RAY);
        bank.keep();

        // budget balanced; shouldn't do anything, not even heal
        assertGt(bank.joy(), 1);
        assertEq(bank.joy(), bank.sin() / RAY);
    }

    function test_keep_unbalanced_slightly_more_rico() public
    {
        // set fee == 2 so easy to predict djoy
        file('fee', bytes32(FEE_2X_ANN));

        // frob enough rico to cover sin later, plus a lil extra
        uint amt = bank.sin() / RAY + 1;
        rico_mint(amt, false);

        // djoy after 1y will be just over amt
        skip(BANKYEAR);

        // set dam and bel so it just takes one second to reach target price
        file('dam', bytes32(rinv(bank.pex())));
        file('bel', bytes32(block.timestamp));
        skip(1);

        assertEq(bank.joy(), 0);
        uint self_risk_1 = risk.balanceOf(self);
        bank.keep();
        uint self_risk_2 = risk.balanceOf(self);

        // unlike test_keep_balanced, budget was not balanced
        // -> keep healed
        assertEq(bank.joy(), 1);
        assertGt(self_risk_1, self_risk_2);
    }

    function test_zero_flap() public
    {
        // joy > sin, but joy too small to flap
        force_sin(0);
        force_fees(1);
        bank.keep();

        assertEq(bank.sin(), 0);
        assertEq(bank.joy(), 1);

        // vow leaves at least 1 joy to avoid toggling 0
        // so this keep should flap 0
        uint pre_rico = rico.balanceOf(self);
        uint pre_risk = risk.balanceOf(self);
        bank.keep();
        uint aft_rico = rico.balanceOf(self);
        uint aft_risk = risk.balanceOf(self);

        assertEq(aft_rico, pre_rico);
        assertEq(aft_risk, pre_risk);
    }

    function test_wel() public _check_integrity_after_
    {
        // can't flap more rico than surplus
        // TODO
        //vm.expectRevert(Bank.ErrBound.selector);
        //new Vow(Bank.BankParams(arico, arisk), Vow.VowParams(RAY + 1, RAY, RAY, 0, 0));

        uint wel = RAY / 7;
        file('wel', bytes32(wel));
        bank.frob(self, int(WAD), int(WAD));

        // drip a bunch of joy
        file('fee', bytes32(bank.FEE_MAX()));
        skip(5 * BANKYEAR);
        bank.frob(self, 0, 0);

        // keep should flap 1/7 the joy
        uint joy = bank.joy() - bank.sin() / RAY;
        uint pre_rico = rico.balanceOf(self);
        uint pre_risk = risk.balanceOf(self);

        // set dam and bel so it just takes one second to reach target price
        file('dam', bytes32(rinv(bank.pex())));
        file('bel', bytes32(block.timestamp - 1));
        file('wal', bytes32(RAD));
        bank.keep();

        uint aft_rico = rico.balanceOf(self);
        uint aft_risk = risk.balanceOf(self);

        assertClose(aft_rico - pre_rico, rmul(joy, wel), 100000000000);

        uint act_price = rdiv(pre_risk - aft_risk, aft_rico - pre_rico);
        assertClose(act_price, RAY, 1000000);
    }

    function test_dam() public {
        risk.mint(self, RAD - risk.totalSupply());
        file('bel', bytes32(block.timestamp));
        file('wel', bytes32(RAY));
        file('wal', bytes32(RAD));
        file('dam', bytes32(RAY / 10));

        // no time elapsed, price == pex
        force_fees(bank.sin() / RAY + WAD);
        uint prerisk = risk.balanceOf(self);
        bank.keep();

        assertClose(prerisk - risk.balanceOf(self), rmul(WAD, bank.pex()), BLN);

        // 1s elapsed, price == pex / 10
        skip(1);
        force_fees(bank.sin() / RAY + WAD);
        prerisk = risk.balanceOf(self);
        bank.keep();

        assertClose(prerisk - risk.balanceOf(self), rmul(WAD, bank.pex()) / 10, BLN);

        // 4s elapsed, price == pex / 10000
        skip(4);
        force_fees(bank.sin() / RAY + WAD);
        prerisk = risk.balanceOf(self);
        bank.keep();

        assertClose(
            prerisk - risk.balanceOf(self), rmul(WAD, bank.pex()) / 10000, BLN
        );

        // lots of time elapsed, dam lowers price to 0
        skip(BANKYEAR);
        force_fees(bank.sin() / RAY + WAD);
        prerisk = risk.balanceOf(self);
        bank.keep();
        assertEq(prerisk - risk.balanceOf(self), 0);
    }

    function test_keep_noop_on_deficit() public {
        force_fees(WAD);
        force_sin(bank.joy() * RAY + RAD);

        uint deficit = bank.sin() / RAY - bank.joy();
        bank.keep();

        assertEq(bank.sin() / RAY - bank.joy(), deficit);
    }

    function test_mine() public {
        file('mop', bytes32(uint(999999978035500000000000000)));
        assertEq(bank.chi(), block.timestamp);
        uint prerisk = risk.totalSupply();
        uint lax = bank.lax();
        uint mop = bank.mop();

        bank.mine();
        assertEq(risk.totalSupply(), prerisk);
        assertEq(bank.chi(), block.timestamp);

        skip(1);
        uint pregif = bank.gif();
        uint flate = rmul(bank.wal(), lax);
        bank.mine();
        assertEq(risk.totalSupply(), prerisk + bank.gif() + flate);
        assertEq(bank.gif(), rmul(pregif, mop));
        assertEq(bank.chi(), block.timestamp);

        skip(BANKYEAR);
        prerisk = risk.totalSupply();
        pregif = bank.gif();
        flate = rmul(bank.wal(), lax);
        bank.mine();
        assertEq(risk.totalSupply(), prerisk + (bank.gif() + flate) * BANKYEAR);
        assertClose(bank.gif(), pregif / 2, 1000000);
        assertEq(bank.chi(), block.timestamp);

        prerisk = risk.totalSupply();
        pregif  = bank.gif();
        bank.mine();
        assertEq(risk.totalSupply(), prerisk);
        assertEq(bank.chi(), block.timestamp);

        assertEq(risk.totalSupply(), risk.balanceOf(self));
    }

    function test_gif() public {
        file('mop', bytes32(RAY));
        file('lax', 0);
        file('gif', bytes32(WAD * 3));

        skip(BANKYEAR);
        uint prerisk = risk.totalSupply();
        bank.mine();
        assertEq(risk.totalSupply(), prerisk + WAD * 3 * BANKYEAR);

        skip(10);
        file('gif', 0);
        prerisk = risk.totalSupply();
        bank.mine();
        assertEq(risk.totalSupply(), prerisk);
    }

    function test_mop() public {
        file('gif', bytes32(WAD));
        file('mop', 0);
        file('lax', 0);

        skip(1);
        uint prerisk = risk.totalSupply();
        bank.mine();
        assertEq(risk.totalSupply(), prerisk);
        assertEq(bank.gif(), 0);

        skip(1000);
        prerisk = risk.totalSupply();
        bank.mine();
        assertEq(risk.totalSupply(), prerisk);
        assertEq(bank.gif(), 0);

        file('gif', bytes32(WAD));
        file('mop', bytes32(RAY / 2));
        skip(2);
        prerisk = risk.totalSupply();
        bank.mine();
        assertEq(risk.totalSupply(), prerisk + WAD / 4 * 2);
        assertEq(bank.gif(), WAD / 4);
    }

    function test_lax() public {
        file('gif', bytes32(WAD));
        file('mop', bytes32(RAY));
        file('lax', 0);

        skip(1);
        uint prerisk = risk.totalSupply();
        bank.mine();
        assertEq(risk.totalSupply(), prerisk + WAD);

        skip(1);
        prerisk = risk.totalSupply();
        uint prewal = bank.wal();
        uint lax = RAY / 10000000000;
        file('lax', bytes32(lax));
        bank.mine();
        assertEq(risk.totalSupply(), prerisk + WAD + rmul(lax, prewal));

        skip(1);
        prewal = bank.wal();
        prerisk = risk.totalSupply();
        file('lax', bytes32(lax));
        bank.mine();
        assertEq(risk.totalSupply(), prerisk + WAD + rmul(lax, prewal));

        file('mop', 0);
        skip(BANKYEAR);
        prewal = bank.wal();
        prerisk = risk.totalSupply();
        bank.mine();
        assertEq(risk.totalSupply(), prerisk + rmul(lax, prewal) * BANKYEAR);
    }

    function test_keep_wal() public {
        force_fees(bank.sin() / RAY + 1000 * WAD);
        set_flap_price(RAY);

        // keep creates equal changes in risk supply and wal
        uint prewal = bank.wal();
        uint prerisk = risk.totalSupply();
        bank.keep();
        assertFalse(prewal == bank.wal());
        assertFalse(prerisk == risk.totalSupply());
        assertEq(prewal - bank.wal(), prerisk - risk.totalSupply());

        skip(1000);

        // so does mine
        prewal = bank.wal();
        prerisk = risk.totalSupply();
        bank.mine();
        assertFalse(prewal == bank.wal());
        assertFalse(prerisk == risk.totalSupply());
        assertEq(bank.wal() - prewal, risk.totalSupply() - prerisk);
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

        me = address(this);
        bob = new Guy(bank);
        cat = new Guy(bank);
        b = address(bob);
        c = address(cat);

        risk_mint(me, 16000 * WAD);

        file('chop', bytes32(RAY * 11 / 10));

        // fee == 5%/yr == ray(1.05 ** (1/BANKYEAR))
        uint fee = 1000000001546067052200000000;
        file('fee', bytes32(fee));
        bank.frob(me, int(100 * WAD), 0);
        bank.frob(me, int(0), int(99 * WAD));

        // cat frobs some rico and transfers to me
        risk_mint(c, 7000 * WAD);
        cat.frob(c, int(4001 * WAD), int(4000 * WAD));
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
        (uint deal,) = bank.safe(me);
        assertEq(deal, RAY);
    }

    function test_bail_urns_1yr_unsafe() public
    {
        // wait a year, flap the surplus
        skip(BANKYEAR);

        // risk:rico price 1
        set_flap_price(RAY);
        bank.keep();

        (uint deal,) = bank.safe(me);
        assertLt(deal, RAY);

        // should be balanced (enough)
        assertEq(bank.sin(), 0);
        assertEq(bank.joy(), 1);

        // bail the urn frobbed in setup
        assertGt(_ink(me), 0);
        bank.bail(me);

        // urn should be bailed, excess ink should be sent back to urn holder
        uint ink = _ink(me); uint art = _art(me);
        assertEq(art, 0);
        assertEq(ink, 0);

        // more joy and more sin
        uint joy = bank.joy();
        uint sin = bank.sin();
        assertGt(sin / RAY, joy);
        assertGt(joy, 1);
    }

    function test_bail_urns_when_safe() public
    {
        // can't bail a safe urn
        vm.expectRevert(Bank.ErrSafeBail.selector);
        bank.bail(me);

        uint sin0 = bank.sin();
        assertEq(sin0 / RAY, 0);

        skip(BANKYEAR);

        // it's unsafe now; can bail
        bank.bail(me);

        // was just bailed, so now it's safe
        vm.expectRevert(Bank.ErrSafeBail.selector);
        bank.bail(me);
    }

    function test_keep_vow_1yr_drip_flap() public
    {
        // wait a year to drip 5%
        uint initial_total = rico.totalSupply();
        skip(BANKYEAR);

        // risk:rico price 1
        set_flap_price(RAY);

        // should flap
        bank.keep();

        // minted 4099, fee is 1.05. 0.05*4099 as no surplus buffer
        uint final_total = rico.totalSupply();
        assertGe(final_total - initial_total, 204.94e18);
        assertLe(final_total - initial_total, 204.96e18);
    }

    function test_e2e_all_actions() public
    {
        // run a flap and ensure risk is burnt
        // pep a little bit more to account for chop >1 now that liqr is in hook
        file('pep', bytes32(uint(3)));
        uint risk_initial_supply = risk.totalSupply();
        skip(BANKYEAR);

        risk_mint(address(guy), 1000 * WAD);

        set_flap_price(RAY / 2);
        guy.keep();

        uint risk_post_flap_supply = risk.totalSupply();
        assertLt(risk_post_flap_supply, risk_initial_supply + 1000 * WAD * 2);

        // confirm bail trades the risk for rico
        uint joy0 = bank.joy();
        bank.bail(me);
        uint joy1 = bank.joy();
        assertGt(joy1, joy0);
    }

}
