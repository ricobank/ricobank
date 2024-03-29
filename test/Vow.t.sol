// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import { Ward } from '../lib/feedbase/src/mixin/ward.sol';
import { Vat, Vow, File, Bank, RicoSetUp, WethLike } from "./RicoHelper.sol";
import { Guy, FrobHook, ZeroHook } from "./RicoHelper.sol";
import { Ball, ERC20Hook, Gem } from "./RicoHelper.sol";
import { Asset, PoolArgs } from "./UniHelper.sol";
import { Math } from '../src/mixin/math.sol';
import { Hook } from '../src/hook/hook.sol';

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

        // some risk mint ramp values
        File(bank).file('rel', bytes32(File(bank).REL_MAX()));
        File(bank).file('bel', bytes32(uint(0)));
        File(bank).file('cel', bytes32(uint(600)));

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

        // risk:rico price 1
        File(bank).file('dom', bytes32(rinv(Vow(bank).pex())));
    }

    function test_flap_price() public
    {
        uint borrow = WAD;

        // risk:rico price 0.1
        // gold:ref price 1k
        uint rico_price_in_risk = 10;

        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        Vat(bank).frob(gilk, self, abi.encodePacked(WAD), int(borrow));

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

    function test_flop_price() public
    {

        uint borrow = WAD * 10000;
        // gold:ref price 10k
        feedpush(grtag, bytes32(10000 * RAY), type(uint).max);
        Vat(bank).frob(gilk, self, abi.encodePacked(WAD), int(borrow));

        // risk:rico price 10
        uint risk_price_in_rico = 10 * RAY;
        uint dom = rmul(rinv(Vow(bank).pex()), risk_price_in_rico);
        File(bank).file('dom', bytes32(dom));
        skip(1);

        uint self_rico_1 = rico.balanceOf(self);
        uint self_risk_1 = risk.balanceOf(self);

        Vow(bank).keep(single(gilk));

        uint rico_cost = self_rico_1 - rico.balanceOf(self);
        uint risk_gain = risk.balanceOf(self) - self_risk_1;

        // rico system takes on deficit auction should be proportional to elapsed
        assertClose(rdiv(rico_cost, risk_gain), risk_price_in_rico, 1000000000);
    }


    function test_basic_keep_deficit() public
    {
        // gold:ref price 1k
        feedpush(grtag, bytes32(1000 * RAY), block.timestamp + 1000);
        Vat(bank).frob(gilk, self, abi.encodePacked(WAD), int(WAD));

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
        Vat(bank).frob(gilk, self, abi.encodePacked(WAD), int(3000 * WAD));

        skip(1);

        // add on a couple ilks so keep does more than one loop iteration
        bytes32[] memory gilks = new bytes32[](2);
        gilks[0] = gilk; gilks[1] = gilk;
        Vow(bank).keep(gilks);
    }

    function test_risk_ramp_is_used() public
    {
        // goldusd, par, and liqr all = 1 after setup
        // art == 10 * ink
        feedpush(grtag, bytes32(RAY * 1000), block.timestamp + 1000);
        Vat(bank).frob(gilk, address(this), abi.encodePacked(1000 * WAD), int(10000 * WAD));

        // set mint ramp higher to use risk ramp
        uint supply = risk.totalSupply();
        File(bank).file('rel', bytes32(File(bank).REL_MAX() - 10));
        File(bank).file('bel', bytes32(block.timestamp - 1));
        File(bank).file('cel', bytes32(uint(1)));

        // setup frobbed to edge, dropping gold price puts system way underwater
        feedpush(grtag, bytes32(RAY), block.timestamp + 10000);

        // create the sin and kick off risk sale
        vm.expectCall(bank, abi.encodePacked(Vat.bail.selector));
        Vat(bank).bail(gilk, self);

        // risk:rico price 1k...test risk mint amount
        feedpush(RISK_RICO_TAG, bytes32(1000 * RAY), block.timestamp + 1000);
        Vow(bank).keep(single(gilk));
        assertEq(risk.totalSupply(), supply + rmul(supply, Vow(bank).ramp().rel));
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
        Vat(bank).frob(gilk, address(this), abi.encodePacked(WAD), int(WAD));

        // wipe previous frob
        uint firstrico = rico.balanceOf(self);
        rico_mint(1, false); // vat burns 1 extra to round in system's favor
        Vat(bank).frob(gilk, address(this), abi.encodePacked(-int(WAD)), -int(WAD));

        skip(BANKYEAR);

        // test rack, frob auto drips so should be able to draw double after a year at 2X fee
        Vat(bank).frob(gilk, address(this), abi.encodePacked(WAD), int(WAD * 1));
        assertClose(rico.balanceOf(self), firstrico * 2, 1_000_000);
        rico_mint(1, false); // rounding
        Vat(bank).frob(gilk, address(this), abi.encodePacked(-int(WAD)), -int(WAD));
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

    function test_keep_unbalanced_slightly_more_sin() public
    {
        // mint enough to cover sin plus one extra
        uint amt = Vat(bank).sin() / RAY - 1;
        rico_mint(amt, false);

        Vat(bank).drip(gilk);

        // set dom and bel so it just takes one second to reach target price
        File(bank).file('dom', bytes32(rinv(Vow(bank).pex())));
        File(bank).file('bel', bytes32(block.timestamp));
        skip(1);

        assertEq(Vat(bank).joy(), 0);
        uint risk_ts1 = risk.totalSupply();
        force_fees(amt);
        Vow(bank).keep(empty);
        uint risk_ts2 = risk.totalSupply();

        // sin == RAY * (joy + 1)
        assertGt(Vat(bank).joy(), 1);
        assertEq(Vat(bank).sin(), 2 * RAY);

        // flop is clipped to deficit, so should only mint 1 (absolute) risk
        assertEq(risk_ts2, risk_ts1 + 1);
    }

    function test_loot() public
    {
        // set protocol fee == 1/3 of every flop
        File(bank).file('loot', bytes32(RAY * 2 / 3));
        assertEq(Vow(bank).loot(), RAY * 2 / 3);

        // risk:rico price 0.1
        risk.mint(address(guy), 1000000 * WAD);
        uint riskrico_price = RAY / 10;

        // set dam and bel so it just takes one second to reach target price
        uint dam = rmul(rinv(riskrico_price), rinv(Vow(bank).pex()));
        File(bank).file('dam', bytes32(dam));
        File(bank).file('bel', bytes32(block.timestamp));
        skip(1);

        // frob some rico
        uint amt = 10000 * WAD;
        rico_mint(amt, false);

        // guy will fill the flap
        vm.startPrank(address(guy));

        // wait a few years and keep
        skip(BANKYEAR * 10);

        uint guys   = rico.balanceOf(address(guy));
        uint selfs  = rico.balanceOf(self);
        uint burned = risk.balanceOf(address(guy));

        vm.stopPrank();
        File(bank).file('bel', bytes32(block.timestamp - 1));
        vm.startPrank(address(guy));

        uint price = rinv(riskrico_price);

        Vow(bank).keep(single(gilk));

        // owner and guy's portions of the flap
        guys  = rico.balanceOf(address(guy)) - guys;
        selfs = rico.balanceOf(self) - selfs;
        burned = burned - risk.balanceOf(address(guy));

        // check that owner got about 1/3 of what keeper got
        assertClose(guys, selfs * 2, 100000);
        assertClose(burned, rmul(guys, price), 100000);

        vm.stopPrank();

        // try with loot == 100%...so protocol takes whole flap
        File(bank).file('loot', bytes32(0));

        // skip 1 to dam the price back down
        skip(1);

        vm.startPrank(address(guy));

        // wait a few years and keep
        skip(BANKYEAR * 10);
        guys  = rico.balanceOf(address(guy));
        selfs = rico.balanceOf(self);
        Vow(bank).keep(single(gilk));

        // owner and guy's portions of the flap
        guys  = rico.balanceOf(address(guy)) - guys;
        selfs = rico.balanceOf(self) - selfs;

        // check that owner got everything
        assertEq(guys, 0);
        assertGt(selfs, 0);

        vm.stopPrank();
    }

    function test_high_loot() public {
        // loot can't be > 100%
        File(bank).file('loot', bytes32(RAY));
        vm.expectRevert(Bank.ErrBound.selector);
        File(bank).file('loot', bytes32(RAY + 1));
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
        Vat(bank).frob(gilk, self, abi.encodePacked(int(WAD)), int(WAD));

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

    function test_time_elapsed_but_zero_flop() public {
        // flop is 0 because of rel, not because of timestamp - bel
        File(bank).file('rel', bytes32(0));
        force_sin(RAD);
        force_fees(WAD / 2);

        skip(1000);

        vm.expectRevert(Vow.ErrReflop.selector);
        Vow(bank).keep(empty);
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

    function test_dom() public {
        File(bank).file('bel', bytes32(block.timestamp));
        File(bank).file('dom', bytes32(RAY / 10));

        rico_mint(WAD * 1000, false);
        force_sin((Vat(bank).joy() + WAD) * RAY);

        // 1s elapsed, price == pex / 10
        skip(1);
        uint prerico = rico.balanceOf(self);
        uint prerisk = risk.balanceOf(self);
        Vow(bank).keep(empty);
        uint aftrico = rico.balanceOf(self);
        uint aftrisk = risk.balanceOf(self);

        assertEq(rdiv(prerico - aftrico, aftrisk - prerisk), Vow(bank).pex() / 10);

        // 4s elapsed, price == pex / 10000
        skip(4);
        force_sin((Vat(bank).joy() + WAD) * RAY);
        prerico = rico.balanceOf(self);
        prerisk = risk.balanceOf(self);
        Vow(bank).keep(empty);
        aftrico = rico.balanceOf(self);
        aftrisk = risk.balanceOf(self);

        assertEq(rdiv(prerico - aftrico, aftrisk - prerisk), Vow(bank).pex() / 10000);

        // lots of time elapsed, dom lowers price to 0
        skip(BANKYEAR);
        force_sin((Vat(bank).joy() + WAD) * RAY);
        prerico = rico.balanceOf(self);
        prerisk = risk.balanceOf(self);
        Vow(bank).keep(empty);
        aftrico = rico.balanceOf(self);
        aftrisk = risk.balanceOf(self);

        assertEq(rdiv(prerico - aftrico, aftrisk - prerisk), 0);
    }

    function test_bel_new_deficit() public {
        uint gain = WAD * 10;
        Vat(bank).filk(gilk, 'fee', bytes32(RAY));
        assertEq(Vow(bank).ramp().bel, block.timestamp);

        // not enough new sin to update bel
        skip(BANKYEAR);
        force_fees(gain);
        force_sin(Vat(bank).joy() * RAY - RAD);
        rico_mint(WAD, true);
        assertEq(Vow(bank).ramp().bel, block.timestamp - BANKYEAR);

        // just enough new sin to update bel
        force_fees(gain);
        force_sin(Vat(bank).joy() * RAY - RAD + RAY);
        rico_mint(WAD, true);
        assertEq(Vow(bank).ramp().bel, block.timestamp);

        // enough old sin to update bel
        skip(BANKYEAR);
        force_fees(gain);
        force_sin(Vat(bank).joy() * RAY + RAY - 1);
        rico_mint(WAD, true);
        assertEq(Vow(bank).ramp().bel, block.timestamp);

        // not enough old sin to update bel
        skip(BANKYEAR);
        force_fees(gain);
        force_sin(Vat(bank).joy() * RAY + RAY);
        rico_mint(WAD, true);
        assertEq(Vow(bank).ramp().bel, block.timestamp - BANKYEAR);
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
        Vat(bank).frob(wilk, me, abi.encodePacked(100 * WAD), 0);
        Vat(bank).frob(wilk, me, abi.encodePacked(int(0)), int(99 * WAD));

        // cat frobs some rico and transfers to me
        cat.deposit{value: 7000 * WAD}();
        cat.approve(address(weth), bank, UINT256_MAX);
        cat.frob(wilk, c, abi.encodePacked(4001 * WAD), int(4000 * WAD));
        cat.transfer(arico, me, 4000 * WAD);

        // used to setup uni pools here, no more though
        // transfer the rico to 1 instead so balances/supplies are same
        dai.transfer(address(1), 2000 * WAD);
        rico.transfer(address(1), 4000 * WAD);
        risk.transfer(address(1), 2000 * WAD);

        File(bank).file('rel', bytes32(File(bank).REL_MAX()));
        File(bank).file('bel', bytes32(block.timestamp));
        File(bank).file('cel', bytes32(uint(1)));

        guy = new Guy(bank);
    }

    function test_init_conditions() public
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
        vm.expectCall(address(tokhook), abi.encodePacked(ERC20Hook.bailhook.selector));
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
        vm.expectCall(address(tokhook), abi.encodePacked(tokhook.bailhook.selector));
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

    function test_keep_vow_1yr_drip_flop() public
    {
        // wait a year, bail the existing urns
        // bails will drip some rico, but should still create a deficit
        skip(BANKYEAR);

        // weth:ref price crash to 0.5
        feedpush(wrtag, bytes32(RAY / 2), UINT256_MAX);
        vm.expectCall(address(tokhook), abi.encodePacked(tokhook.bailhook.selector));
        Vat(bank).bail(wilk, me);

        // borrow some rico to fill the flip for cat's urn
        rico_mint(WAD * 5000, false);
        Vat(bank).bail(wilk, address(cat));

        // more sin than rico, should flop
        set_dxm('dom', RAY);
        uint pre_risk = risk.balanceOf(self);
        Vow(bank).keep(single(wilk));
        assertGt(risk.balanceOf(self), pre_risk);
    }

    function test_keep_rate_limiting_flop() public
    {
        // high ceil, high line
        File(bank).file('ceil', bytes32(uint(100000 * RAD)));
        Vat(bank).filk(wilk, 'line', bytes32(uint(100000 * RAD)));

        set_dxm('dom', RAY);
        // 1s passed since bel
        File(bank).file('rel', bytes32(RAY / BANKYEAR));
        File(bank).file('cel', bytes32(uint(BANKYEAR)));

        // keep should flop totalSupply risk, since rel will give 100% after a year
        uint risksupply = risk.totalSupply();
        prepguyrico(10000 * WAD, true);
        File(bank).file('bel', bytes32(uint(block.timestamp - 2)));
        guy.keep(single(wilk));
        assertClose(risk.totalSupply(), risksupply + risksupply * 2 / BANKYEAR, 1_000_000);
    }

    function test_e2e_all_actions() public
    {
        // run a flap and ensure risk is burnt
        // pep a little bit more to account for chop >1 now that liqr is in hook
        Vat(bank).filh(wilk, 'pep', empty, bytes32(uint(3)));
        uint risk_initial_supply = risk.totalSupply();
        skip(BANKYEAR);

        risk.mint(address(guy), 1000 * WAD);
        File(bank).file('rel', bytes32(File(bank).REL_MAX()));

        set_dxm('dam', RAY / 2);
        guy.keep(single(wilk));

        uint risk_post_flap_supply = risk.totalSupply();
        assertLt(risk_post_flap_supply, risk_initial_supply + 1000 * WAD * 2);

        // confirm bail trades the weth for rico
        feedpush(wrtag, bytes32(RAY / 10), UINT256_MAX);
        uint joy0 = Vat(bank).joy();
        vm.expectCall(address(tokhook), abi.encodePacked(tokhook.bailhook.selector));
        Vat(bank).bail(wilk, me);
        uint joy1 = Vat(bank).joy();
        assertGt(joy1, joy0);

        // bail price was too low to cover, now have deficit
        set_dxm('dom', RAY / 10);
        uint pre_flop_deficit = Vat(bank).sin() / RAY - Vat(bank).joy();
        prepguyrico(2000 * WAD, false);
        guy.keep(single(wilk));

        // after flop bank should have more joy
        uint post_flop_deficit = Vat(bank).sin() / RAY - Vat(bank).joy();
        assertLt(post_flop_deficit, pre_flop_deficit);
    }

    function test_flop_clipping() public
    {
        // wait 10s to drip a little bit
        skip(10);
        feedpush(wrtag, bytes32(0), UINT256_MAX);
        // cause bank deficit by flipping with zero price
        Vat(bank).bail(wilk, me);

        // set rel small so first flop will not cover deficit
        File(bank).file('rel', bytes32(RAY / WAD));
        File(bank).file('cel', bytes32(uint(5)));

        set_dxm('dom', RAY * WAD / 10); skip(17);
        Bank.Ramp memory ramp = Vow(bank).ramp();
        uint flop = rmul(ramp.rel, risk.totalSupply());
        flop     *= min(block.timestamp - ramp.bel, ramp.cel);

        prepguyrico(2000 * WAD, false);
        uint ts0 = risk.totalSupply();
        uint gr0 = rico.balanceOf(address(guy));
        guy.keep(single(wilk));
        uint ts1 = risk.totalSupply();
        uint gr1 = rico.balanceOf(address(guy));
        uint price_unclipped = wdiv(gr0 - gr1, ts1 - ts0);

        // with small rel, flop size should not have been clipped
        assertEq(flop, ts1 - ts0);

        skip(2);
        // charge up large cell
        File(bank).file('cel', bytes32(BANKYEAR));
        File(bank).file('bel', bytes32(block.timestamp - BANKYEAR));
        Vat(bank).drip(WETH_ILK);

        uint under = Vat(bank).sin() / RAY - Vat(bank).joy();
        uint ts2   = risk.totalSupply();
        uint gr2   = rico.balanceOf(address(guy));
        // price risk high, should clip
        set_dxm('dom', RAY * WAD); skip(2);
        guy.keep(empty);
        uint ts3   = risk.totalSupply();
        uint gr3   = rico.balanceOf(address(guy));
        // with large rel flop size should have been clipped
        assertEq(under, gr2 - gr3);

        // a clipped flop should leave bank with neither a surplus nor deficit
        uint joy = Vat(bank).joy();
        uint sin = Vat(bank).sin() / RAY;
        assertEq(joy, sin);

        // the first flop was small, prices should be proportional to their tugs
        uint price_clipped = wdiv(gr2 - gr3, ts3 - ts2);
        assertClose(price_clipped, price_unclipped * WAD, 99);

        // should only advance bel < 1% of cell bc deficit was tiny
        assertLt(Vow(bank).ramp().bel, block.timestamp);
    }

    function test_sparse_flop_bel() public
    {
        // test bel when elapsed time is >> cel
        uint cel = 1000;
        uint dom = RAY * 999982 / 1000000;
        File(bank).file('cel', bytes32(cel));
        File(bank).file('dom', bytes32(dom));

        // cause bank deficit by flipping with lower price
        feedpush(wrtag, bytes32(RAY * 10 / 11), UINT256_MAX);
        Vat(bank).bail(wilk, me);

        // set rel max so flop is clipped
        File(bank).file('rel', bytes32(File(bank).REL_MAX()));

        // elapse a lot more than cel
        uint elapsed = cel * 1000;
        skip(elapsed);
        Vat(bank).drip(gilk);
        Vow(bank).keep(empty);

        // elapsed time > cel
        // -> bel should advance from new timestamp - cel, not last timestamp
        uint bel = Vow(bank).ramp().bel;
        assertGt(bel, block.timestamp - cel);
        assertLt(bel, block.timestamp);
    }

}
