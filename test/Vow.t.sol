// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.25;

import "forge-std/Test.sol";

import { Ward } from '../lib/feedbase/src/mixin/ward.sol';
import { Vat, Vow, File, Bank, RicoSetUp, WethLike } from "./RicoHelper.sol";
import { Guy } from "./RicoHelper.sol";
import { Ball, Gem } from "./RicoHelper.sol";
import { Asset, PoolArgs } from "./UniHelper.sol";
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
        init_gold();
        ilks.push(gilk);

        // have 10k each of rico, risk and gold
        gold.approve(router, type(uint256).max);
        rico.approve(router, type(uint256).max);
        risk.approve(router, type(uint256).max);
        gold.approve(bank, type(uint256).max);

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
        // gold:ref price 1k
        uint rico_price_in_risk = 10;

        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        Vat(bank).frob(gilk, self, int(WAD), int(borrow));

        // accumulate a bunch of fees
        skip(BANKYEAR);
        Vat(bank).drip(gilk);

        // joy depends on tart and change in rack
        uint surplus = Vat(bank).joy();
        uint rack    = Vat(bank).ilks(gilk).rack;
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
        File(bank).file('dam', bytes32(dam));
        File(bank).file('bel', bytes32(block.timestamp));
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
        // gold:ref price 1k
        feedpush(grtag, bytes32(1000 * RAY), block.timestamp + 1000);
        Vat(bank).frob(gilk, self, int(WAD), int(WAD));

        // big crash, gold:ref price 0.  bail creates some sin
        feedpush(grtag, bytes32(RAY * 0), block.timestamp + 1000);
        Vat(bank).bail(gilk, self);

        // create some rico to pay for the flop
        rico_mint(1000 * WAD, false);

        // add on a couple ilks so keep does more than one loop iteration
        skip(1);
        bytes32[] memory gilks = new bytes32[](2);
        gilks[0] = gilk; gilks[1] = gilk;
        Vow(bank).keep(gilks);
    }

    function test_basic_keep_surplus() public
    {
        // set fee > 1 so rack changes
        Vat(bank).filk(gilk, 'fee', bytes32(FEE_2X_ANN));

        // gold:ref price 10k
        feedpush(grtag, bytes32(10000 * RAY), block.timestamp + 1000);
        Vat(bank).frob(gilk, self, int(WAD), int(3000 * WAD));

        skip(1);

        // add on a couple ilks so keep does more than one loop iteration
        bytes32[] memory gilks = new bytes32[](2);
        gilks[0] = gilk; gilks[1] = gilk;
        Vow(bank).keep(gilks);
    }

    function test_drip() public
    {
        // should be 0 pending fees
        uint rho = Vat(bank).ilks(gilk).rho;
        assertEq(rho, block.timestamp);
        assertEq(rico.balanceOf(self), 0);

        // set high fee, gold:ref price 1k
        Vat(bank).filk(gilk, 'fee', bytes32(FEE_2X_ANN));
        feedpush(grtag, bytes32(RAY * 1000), type(uint).max);
        Vat(bank).frob(gilk, address(this), int(WAD), int(WAD));

        // wipe previous frob
        uint firstrico = rico.balanceOf(self);
        rico_mint(1, false); // vat burns 1 extra to round in system's favor
        Vat(bank).frob(gilk, address(this), -int(WAD), -int(WAD));

        skip(BANKYEAR);

        // test rack, frob auto drips so should be able to draw double after a year at 2X fee
        Vat(bank).frob(gilk, address(this), int(WAD), int(WAD * 1));
        assertClose(rico.balanceOf(self), firstrico * 2, 1_000_000);
        rico_mint(1, false); // rounding
        Vat(bank).frob(gilk, address(this), -int(WAD), -int(WAD));
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
        Vat(bank).filk(gilk, 'fee', bytes32(FEE_2X_ANN));

        // frob enough rico to cover sin later, plus a lil extra
        uint amt = Vat(bank).sin() / RAY + 1;
        rico_mint(amt, false);

        // djoy after 1y will be just over amt
        skip(BANKYEAR);

        // set dam and bel so it just takes one second to reach target price
        File(bank).file('dam', bytes32(rinv(Vow(bank).pex())));
        File(bank).file('bel', bytes32(block.timestamp));
        skip(1);

        assertEq(Vat(bank).joy(), 0);
        uint self_risk_1 = risk.balanceOf(self);
        Vow(bank).keep(single(gilk));
        uint self_risk_2 = risk.balanceOf(self);

        // unlike test_keep_balanced, budget was not balanced
        // -> keep healed
        assertEq(Vat(bank).joy(), 1);
        assertGt(self_risk_1, self_risk_2);
    }

    function test_zero_flap() public
    {
        // risk:rico price 1
        feedpush(RISK_RICO_TAG, bytes32(RAY), type(uint).max);

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
        File(bank).file('wel', bytes32(RAY + 1));

        uint wel = RAY / 7;
        File(bank).file('wel', bytes32(wel));
        Vat(bank).frob(gilk, self, int(WAD), int(WAD));

        // drip a bunch of joy
        Vat(bank).filk(gilk, 'fee', bytes32(Vat(bank).FEE_MAX()));
        skip(5 * BANKYEAR);
        Vat(bank).drip(gilk);

        // keep should flap 1/7 the joy
        uint joy = Vat(bank).joy() - Vat(bank).sin() / RAY;
        uint pre_rico = rico.balanceOf(self);
        uint pre_risk = risk.balanceOf(self);

        // set dam and bel so it just takes one second to reach target price
        File(bank).file('dam', bytes32(rinv(Vow(bank).pex())));
        File(bank).file('bel', bytes32(block.timestamp - 1));
        Vow(bank).keep(empty);

        uint aft_rico = rico.balanceOf(self);
        uint aft_risk = risk.balanceOf(self);

        assertClose(aft_rico - pre_rico, rmul(joy, wel), 100000000000);

        uint act_price = rdiv(pre_risk - aft_risk, aft_rico - pre_rico);
        assertClose(act_price, RAY, 1000000);
    }

    function test_dam() public {
        risk.mint(self, UINT256_MAX - risk.totalSupply());
        File(bank).file('bel', bytes32(block.timestamp));
        File(bank).file('wel', bytes32(RAY));
        File(bank).file('dam', bytes32(RAY / 10));

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

}

contract Usr is Guy {
    WethLike weth;
    constructor(address payable _bank, WethLike _weth) Guy(_bank) {
        weth = _weth;
    }
    function deposit() public payable {
        weth.deposit{value: msg.value}();
    }
}

contract VowJsTest is Test, RicoSetUp {
    // me == js ALI
    address me;
    Usr bob;
    Usr cat;
    address b;
    address c;
    WethLike weth;
    bytes32 constant wilk = WETH_ILK;

    function setUp() public
    {
        make_bank();
        init_dai();
        init_gold();

        weth = WethLike(WETH);
        me = address(this);
        bob = new Usr(bank, weth);
        cat = new Usr(bank, weth);
        b = address(bob);
        c = address(cat);

        weth.deposit{value: 6000 * WAD}();
        risk.mint(me, 10000 * WAD);
        weth.approve(bank, UINT256_MAX);
        dai.approve(bank, UINT256_MAX);

        File(bank).file('ceil', bytes32(uint(10000 * RAD)));
        Vat(bank).filk(wilk, 'line', bytes32(10000 * RAD));
        Vat(bank).filk(wilk, 'chop', bytes32(RAY * 11 / 10));

        // weth:ref price 1
        // gold:ref price 1
        feedpush(wrtag, bytes32(RAY), block.timestamp + 2 * BANKYEAR);
        feedpush(grtag, bytes32(RAY), block.timestamp + 2 * BANKYEAR);

        // fee == 5%/yr == ray(1.05 ** (1/BANKYEAR))
        uint fee = 1000000001546067052200000000;
        Vat(bank).filk(wilk, 'fee', bytes32(fee));
        Vat(bank).frob(wilk, me, int(100 * WAD), 0);
        Vat(bank).frob(wilk, me, int(0), int(99 * WAD));

        // cat frobs some rico and transfers to me
        cat.deposit{value: 7000 * WAD}();
        cat.approve(address(weth), bank, UINT256_MAX);
        cat.frob(wilk, c, int(4001 * WAD), int(4000 * WAD));
        cat.transfer(arico, me, 4000 * WAD);

        // used to setup uni pools here, no more though
        // transfer the rico to 1 instead so balances/supplies are same
        dai.transfer(address(1), 2000 * WAD);
        rico.transfer(address(1), 4000 * WAD);
        risk.transfer(address(1), 2000 * WAD);

        File(bank).file('bel', bytes32(block.timestamp));

        guy = new Guy(bank);
    }

    function test_init_conditions() public view
    {
        // frobbed the rico and no time has passed, so should be safe
        assertEq(rico.balanceOf(me), 99 * WAD);
        (Vat.Spot safe1,,) = Vat(bank).safe(wilk, me);
        assertEq(uint(safe1), uint(Vat.Spot.Safe));
    }

    function test_bail_urns_1yr_unsafe() public
    {
        // wait a year, flap the surplus
        skip(BANKYEAR);

        // risk:rico price 1
        set_dxm('dam', RAY);
        Vow(bank).keep(single(wilk));

        (Vat.Spot spot,,) = Vat(bank).safe(wilk, me);
        assertEq(uint(spot), uint(Vat.Spot.Sunk));

        // should be balanced (enough)
        assertEq(Vat(bank).sin(), 0);
        assertEq(Vat(bank).joy(), 1);

        // bail the urn frobbed in setup
        assertGt(_ink(wilk, me), 0);
        Vat(bank).bail(wilk, me);

        // urn should be bailed, excess ink should be sent back to urn holder
        uint ink = _ink(wilk, me); uint art = _art(wilk, me);
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
        Vat(bank).bail(wilk, me);

        uint sin0 = Vat(bank).sin();
        assertEq(sin0 / RAY, 0);

        skip(BANKYEAR);
        feedpush(wrtag, bytes32(0), UINT256_MAX);

        // it's unsafe now; can bail
        Vat(bank).bail(wilk, me);

        // was just bailed, so now it's safe
        vm.expectRevert(Vat.ErrSafeBail.selector);
        Vat(bank).bail(wilk, me);
    }

    function test_keep_vow_1yr_drip_flap() public
    {
        // wait a year to drip 5%
        uint initial_total = rico.totalSupply();
        skip(BANKYEAR);

        // risk:rico price 1
        set_dxm('dam', RAY);

        // should flap
        Vow(bank).keep(single(wilk));

        // minted 4099, fee is 1.05. 0.05*4099 as no surplus buffer
        uint final_total = rico.totalSupply();
        assertGe(final_total - initial_total, 204.94e18);
        assertLe(final_total - initial_total, 204.96e18);
    }

    function test_e2e_all_actions() public
    {
        // run a flap and ensure risk is burnt
        // pep a little bit more to account for chop >1 now that liqr is in hook
        Vat(bank).filk(wilk, 'pep', bytes32(uint(3)));
        uint risk_initial_supply = risk.totalSupply();
        skip(BANKYEAR);

        risk.mint(address(guy), 1000 * WAD);

        set_dxm('dam', RAY / 2);
        guy.keep(single(wilk));

        uint risk_post_flap_supply = risk.totalSupply();
        assertLt(risk_post_flap_supply, risk_initial_supply + 1000 * WAD * 2);

        // confirm bail trades the weth for rico
        feedpush(wrtag, bytes32(RAY / 10), UINT256_MAX);
        uint joy0 = Vat(bank).joy();
        Vat(bank).bail(wilk, me);
        uint joy1 = Vat(bank).joy();
        assertGt(joy1, joy0);
    }

}
