// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.25;

import "forge-std/Test.sol";

import { Vat, Vow, File, Ball } from '../src/ball.sol';
import { RicoSetUp, Guy } from "./RicoHelper.sol";
import { BankDiamond } from '../src/diamond.sol';
import { Bank, Math, Gem } from '../src/bank.sol';

contract VatTest is Test, RicoSetUp {
    uint constant init_join = 1000;
    uint constant stack      = WAD * 10;

    address[] gems;
    uint256[] wads;

    function setUp() public {
        make_bank();
        init_gold();
        gold.mint(bank, init_join * WAD);

        // non-self user
        guy = new Guy(bank);
    }

    function test_frob_basic() public {
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        Vat(bank).frob(gilk, self, int(WAD), int(WAD));
        Vat(bank).frob(gilk, self, int(WAD), int(WAD));
    }

    function test_drip_basic() public {
        // set fee to something >1 so joy changes
        Vat(bank).drip(gilk);
        Vat(bank).filk(gilk, 'fee', bytes32(FEE_2X_ANN));

        skip(1);

        // frob retroactively, drip the profits
        Vat(bank).frob(gilk, self, int(100 * WAD), int(50 * WAD));
        Vat(bank).drip(gilk);
    }

    function test_ilk_reset() public {
        // can't set an ilk twice
        vm.expectRevert(Vat.ErrMultiIlk.selector);
        Vat(bank).init(gilk, agold);
    }

    ///////////////////////////////////////////////
    // urn safety tests
    ///////////////////////////////////////////////

    // gold:usd, par, and liqr all = 1 after set up
    function test_create_unsafe() public {
        // art should not exceed ink, because price par liqr all == 1
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(gilk, address(this), int(stack), int(stack) + 1);

        // skip past feed expiration
        (,uint ttl) = feedpull(grtag);
        skip(ttl - block.timestamp + 100);

        // shouldn't be able to frob to less safe position if feed is iffy
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(gilk, address(this), int(stack), int(1));
    }

    function test_safe_return_vals() public {
        Vat(bank).frob(gilk, address(this), int(stack), int(stack));
        (Vat.Spot spot, uint deal, uint tot) = Vat(bank).safe(gilk, self);

        // position should be (barely) safe
        assertTrue(spot == Vat.Spot.Safe);

        // when safe deal should be 1
        assertEq(deal, RAY);

        // tot should be feed price as a rad
        (bytes32 val,) = feedpull(grtag);
        uint      tot1 = stack * uint(val);
        assertEq(tot, tot1);

        // drop price to 80%...position should sink underwater
        feedpush(grtag, bytes32(RAY * 4 / 5), block.timestamp + 1000);
        (spot, deal, tot) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Sunk);

        // the deal should now be 0.8
        assertEq(deal, RAY * 4 / 5);
        // collateral value should also be 80% of first result
        assertEq(tot, tot1 * 4 / 5);

        // wait longer than ttl so price feed is stale
        // safe should be iffy
        skip(1100);
        (spot, deal, tot) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Iffy);

        // it's safe even when stale if debt is zero
        rico_mint(WAD, true);
        Vat(bank).frob(gilk, address(this), int(0), - int(_art(gilk, self)));
        (spot, deal, tot) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);
    }

    function test_rack_puts_urn_underwater() public {
        // frob till barely safe
        Vat(bank).frob(gilk, address(this), int(stack), int(stack));
        (Vat.Spot spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);

        // accrue some interest to sink
        skip(100);
        Vat(bank).drip(gilk);
        (spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Sunk);

        // can't refloat using fee, because fee must be >=1
        vm.expectRevert(Bank.ErrBound.selector);
        Vat(bank).filk(gilk, 'fee', bytes32(RAY - 1));
    }

    function test_liqr_puts_urn_underwater() public {
        // frob till barely safe
        Vat(bank).frob(gilk, address(this), int(stack), int(stack));
        (Vat.Spot spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);

        // raise liqr a little bit...should sink the urn
        Vat(bank).filk(gilk, 'liqr', bytes32(RAY + 1000000));
        (spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Sunk);

        // can't have liqr < 1
        vm.expectRevert(Bank.ErrBound.selector);
        Vat(bank).filk(gilk, 'liqr', bytes32(RAY - 1));

        // lower liqr back down...should refloat the urn
        Vat(bank).filk(gilk, 'liqr', bytes32(RAY));
        (spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);
    }

    function test_gold_crash_sinks_urn() public {
        // frob till barely safe
        Vat(bank).frob(gilk, address(this), int(stack), int(stack));
        (Vat.Spot spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);

        // crash gold price...should sink the urn
        feedpush(grtag, bytes32(RAY / 2), block.timestamp + 1000);
        (spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Sunk);

        // no one bailed, now pump gold price back up.  should refloat
        feedpush(grtag, bytes32(RAY * 2), block.timestamp + 1000);
        (spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);
    }

    function test_time_makes_urn_iffy() public {
        // frob till barely safe
        Vat(bank).frob(gilk, address(this), int(stack), int(stack));
        (Vat.Spot spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);

        // let the feed expire...should make the urn iffy
        (,uint ttl) = feedpull(grtag);
        skip(ttl - block.timestamp + 100);
        (spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Iffy);

        // without a drip an update should refloat urn
        feedpush(grtag, bytes32(RAY), block.timestamp + 1000);
        (spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);
    }

    function test_free_without_feed() public {
        Vat(bank).frob(gilk, address(this), int(stack), int(10));
        // make feed stale
        feedpush(grtag, bytes32(RAY), block.timestamp);
        skip(1);
        // while debt is non zero withdrawing collateral should fail
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(gilk, address(this), int(-1), int(0));
        // should still be able to pay off debt
        rico_mint(WAD, true);
        Vat(bank).frob(gilk, address(this), int(0), - int(_art(gilk, self)));
        // with zero debt and stale feed should be able to withdraw collateral
        Vat(bank).frob(gilk, address(this), -int(stack), int(0));
        assertEq(_ink(gilk, self), 0);
    }

    function test_frob_refloat() public {
        // frob till barely safe
        Vat(bank).frob(gilk, address(this), int(stack), int(stack));
        (Vat.Spot spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);

        // sink the urn
        feedpush(grtag, bytes32(RAY / 2), block.timestamp + 1000);
        (spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Sunk);

        // add ink to refloat
        Vat(bank).frob(gilk, address(this), int(stack), int(0));
        (spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);
    }

    function test_increasing_risk_sunk_urn() public {
        // frob till barely safe
        Vat(bank).frob(gilk, address(this), int(stack), int(stack));
        (Vat.Spot spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);

        // sink it
        feedpush(grtag, bytes32(RAY / 2), block.timestamp + 1000);
        (spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Sunk);

        // should always be able to decrease art or increase ink, even when sunk
        Vat(bank).frob(gilk, address(this), int(0), int(-1));
        Vat(bank).frob(gilk, address(this), int(1), int(0));

        // should not be able to decrease ink or increase art of sunk urn
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(gilk, address(this), int(10), int(1));
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(gilk, address(this), int(-1), int(-1));
    }

    function test_increasing_risk_iffy_urn() public
    {
        // frob till *very* safe
        Vat(bank).frob(gilk, address(this), int(stack), int(10));
        (Vat.Spot spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);

        // let feed expire...should make urn iffy
        (,uint ttl) = feedpull(grtag);
        skip(ttl - block.timestamp + 100);
        (spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Iffy);

        // should always be able to decrease art or increase ink, even when iffy
        Vat(bank).frob(gilk, address(this), int(0), int(-1));
        Vat(bank).frob(gilk, address(this), int(1), int(0));

        // should not be able to decrease ink or increase art of iffy urn
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(gilk, address(this), int(10), int(1));
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(gilk, address(this), int(-1), int(-1));
    }

    function test_increasing_risk_safe_urn() public {
        // frob till very safe
        Vat(bank).frob(gilk, address(this), int(stack), int(10));
        (Vat.Spot spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);

        // should always be able to decrease art or increase ink
        Vat(bank).frob(gilk, address(this), int(0), int(-1));
        Vat(bank).frob(gilk, address(this), int(1), int(0));

        // should be able to decrease ink or increase art of safe urn
        // as long as resulting urn is safe
        Vat(bank).frob(gilk, address(this), int(0), int(1));
        Vat(bank).frob(gilk, address(this), int(-1), int(0));
    }

    function test_basic_bail() public {
        // gold:ref price 1k
        feedpush(grtag, bytes32(1000 * RAY), block.timestamp + 1000);
        Vat(bank).frob(gilk, self, int(WAD), int(WAD));

        // big crash and liquidation
        feedpush(grtag, bytes32(0), block.timestamp + 1000);
        Vat(bank).bail(gilk, self);
    }

    function test_bail_price() public {
        // frob to edge of safety
        uint borrow = WAD * 1000;
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        Vat(bank).frob(gilk, self, int(WAD), int(borrow));

        // drop gold/rico to 75%...pep is 2, so earn is cubic
        feedpush(grtag, bytes32(750 * RAY), type(uint).max);
        // price should be 0.75**3, 0.75 for oracle drop and 0.75**2 for deal**pep
        uint expected = wmul(borrow, WAD * 75**3 / 100**3);
        rico_mint(expected, false);
        rico.transfer(address(guy), expected);
        uint earn = guy.bail(gilk, self);
        // check returned bytes represent quantity of tokens received
        assertEq(earn, WAD);

        // guy was given exact amount, check all was spent for all gold deposit
        assertEq(rico.balanceOf(address(guy)), uint(0));
        assertEq(gold.balanceOf(address(guy)), WAD);
    }

    function test_bail_price_pup_1() public {
        // frob to edge of safety
        uint borrow = WAD * 1000;
        uint pep = 1;
        uint pop = 2 * RAY;
        int  pup = -int(RAY);
        Vat(bank).filk(gilk, "pep", bytes32(pep));
        Vat(bank).filk(gilk, "pop", bytes32(pop));
        Vat(bank).filk(gilk, "pup", bytes32(uint(pup)));

        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        Vat(bank).frob(gilk, self, int(WAD), int(borrow));

        // drop gold/rico to 75%...pep is 1, so earn is linear
        feedpush(grtag, bytes32(750 * RAY), type(uint).max);
        uint expected = rmul(borrow, rmul(RAY * 3 / 4, rmash(RAY * 3 / 4, pep, pop, pup)));
        prepguyrico(expected, false);
        uint earn = guy.bail(gilk, self);
        // check returned bytes represent quantity of tokens received
        assertEq(earn, WAD);

        // guy was given exact amount, check all was spent for all gold deposit
        assertEq(rico.balanceOf(address(guy)), uint(0));
        assertEq(gold.balanceOf(address(guy)), WAD);

        // clamping
        pep = 2; pop = 3 * RAY / 2; pup = -int(RAY / 8);
        Vat(bank).filk(gilk, "pep", bytes32(pep));
        Vat(bank).filk(gilk, "pop", bytes32(pop));
        Vat(bank).filk(gilk, "pup", bytes32(uint(pup)));
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        Vat(bank).frob(gilk, self, int(WAD), int(borrow));
        feedpush(grtag, bytes32(250 * RAY), type(uint).max);
        assertEq(guy.bail(gilk, self), WAD);
        assertEq(rico.balanceOf(address(guy)), 0);
    }

    function test_bail_refund() public {
        // set c ratio to double
        uint pop = RAY * 3 / 2;
        uint dink = WAD;
        Vat(bank).filk(gilk, "liqr", bytes32(RAY * 2));
        Vat(bank).filk(gilk, "pep",  bytes32(uint(2)));
        Vat(bank).filk(gilk, "pop",  bytes32(pop));
        uint borrow = WAD * 500;
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        // frob to edge of safety
        Vat(bank).frob(gilk, self, int(dink), int(borrow));

        // drop gold/rico to 75%...position is still overcollateralized
        feedpush(grtag, bytes32(750 * RAY), type(uint).max);

        // price should be 0.75**3x, as 0.75 for oracle drop and 0.75**2 for deal factor
        rico_mint(borrow, false);
        rico.transfer(address(guy), borrow);
        guy.bail(gilk, self);

        // guy should not get all gold, as position was overcollateralized
        // guy gets ink * (borrowed / total ink value)
        uint expected_full = rmul(wmul(borrow * 2, dink * 75**3 / 100**3), pop);
        uint guy_earn      = wmul(dink, wdiv(borrow, expected_full));
        assertEq(gold.balanceOf(address(guy)), guy_earn);

        // excess ink should be sent back to urn holder, not left in urn
        uint ink_left = _ink(gilk, self);
        assertEq(ink_left, WAD - guy_earn);
        assertGt(ink_left, 0);
    }


    //////////////////////////////////////////////////
    // join/exit tests
    //////////////////////////////////////////////////

    function test_rico_join_exit() public {
        uint self_gold_bal0 = gold.balanceOf(self);
        uint self_rico_bal0 = rico.balanceOf(self);

        // revert for trying to join more gems than owned
        vm.expectRevert(Gem.ErrUnderflow.selector);
        Vat(bank).frob(gilk, self, int(self_gold_bal0 + 1), 0);

        // revert for trying to exit too much rico
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(gilk, self, int(10), int(11));

        // revert for trying to exit gems from other users
        vm.expectRevert(Math.ErrUintUnder.selector);
        Vat(bank).frob(gilk, self, int(-1), 0);

        // gems are taken from user when joining, and rico given to user
        Vat(bank).frob(gilk, self, int(stack), int(stack / 2));
        uint self_gold_bal1 = gold.balanceOf(self);
        uint self_rico_bal1 = rico.balanceOf(self);
        assertEq(self_gold_bal1 + stack, self_gold_bal0);
        assertEq(self_rico_bal1, self_rico_bal0 + stack / 2);

        // close, even without drip need 1 extra rico as rounding is in systems favour
        rico_mint(1, false);
        Vat(bank).frob(gilk, self, -int(stack), -int(stack / 2));
        uint self_gold_bal2 = gold.balanceOf(self);
        uint self_rico_bal2 = rico.balanceOf(self);
        assertEq(self_gold_bal0, self_gold_bal2);
        assertEq(self_rico_bal0, self_rico_bal2);
    }

    function test_init_conditions() public view {
        assertEq(BankDiamond(bank).owner(), self);
    }

    function test_rejects_unsafe_frob() public {
        uint ink = _ink(gilk, self);
        uint art = _art(gilk, self);
        assertEq(ink, 0);
        assertEq(art, 0);

        // no collateral...shouldn't be able to borrow
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(gilk, self, int(0), int(WAD));
    }

    // amount of rico owed to pay down the CDP
    function owed() internal returns (uint) {
        // update rack first
        Vat(bank).drip(gilk);

        uint rack = Vat(bank).ilks(gilk).rack;
        uint art = _art(gilk, self);
        return rack * art;
    }

    function test_drip() public {
        // set a high fee
        Vat(bank).filk(gilk, 'fee', bytes32(Vat(bank).FEE_MAX()));

        // drip a little bit so this isn't the first fee accumulation
        skip(1);
        Vat(bank).drip(gilk);
        Vat(bank).frob(gilk, self, int(100 * WAD), int(50 * WAD));

        // wait a second, just so it's more realistic
        skip(1);
        uint debt0 = owed();

        skip(1);
        uint debt1 = owed();
        assertClose(debt1, rmul(debt0, Vat(bank).FEE_MAX()), 1_000_000_000_000);
    }

    function test_rest_monotonic() public {
        // set a tiny fee - will accumulate to rest
        Vat(bank).filk(gilk, 'fee', bytes32(RAY + 2));
        Vat(bank).filk(gilk, 'dust', bytes32(0));

        // frob a tiny bit more than a wad so lower bits of fee go to rest
        Vat(bank).frob(gilk, self, int(WAD + 1), int(WAD + 1));

        // drip to accumulate to rest
        skip(1);
        Vat(bank).drip(gilk);
        assertEq(Vat(bank).rest(), 2 * WAD + 2);

        // drip again, should have more rest now
        skip(1);
        Vat(bank).drip(gilk);
        assertGt(Vat(bank).rest(), 2 * WAD + 2);
    }

    function test_rest_drip_0() public {
        // set a tiny fee and frob
        Vat(bank).filk(gilk, 'fee', bytes32(RAY + 1));
        Vat(bank).frob(gilk, self, int(WAD), int(WAD));

        // didn't frob any fractional rico, so rest should be (fee - RAY) * WAD
        skip(1);
        Vat(bank).drip(gilk);
        assertEq(Vat(bank).rest(), WAD);

        // do it again, should double
        skip(1);
        Vat(bank).drip(gilk);
        assertEq(Vat(bank).rest(), 2 * WAD);

        // no more fee - rest should stop increasing
        Vat(bank).filk(gilk, 'fee', bytes32(RAY));
        skip(1);
        Vat(bank).drip(gilk);
        assertEq(Vat(bank).rest(), 2 * WAD);
    }

    function test_rest_drip_toggle_ones() public {
        // drip with no fees
        Vat(bank).filk(gilk, 'fee', bytes32(RAY));
        Vat(bank).filk(gilk, 'dust', bytes32(0));
        Vat(bank).drip(gilk);

        // mint 1 to deal with rounding
        // then lock 1 and wipe 1
        rico_mint(1, true);
        Vat(bank).frob(gilk, self, int(1), int(1));
        Vat(bank).frob(gilk, self, -int(1), -int(1));

        // rest from rounding should be RAD / WAD == RAY
        Vat(bank).drip(gilk);
        assertEq(Vat(bank).rest(), RAY);

        // dripping should clear rest
        skip(1);
        Vat(bank).drip(gilk);
        assertEq(Vat(bank).rest(), 0);
    }

    function test_rest_drip_toggle_wads() public {
        // drip with no fees
        Vat(bank).filk(gilk, 'fee', bytes32(RAY));
        Vat(bank).drip(gilk);

        // tiny fee, no dust
        Vat(bank).filk(gilk, 'fee', bytes32(RAY + 1));
        Vat(bank).filk(gilk, 'dust', bytes32(0));

        // mint 1 for rounding, then frob and drip
        rico_mint(1, true);
        Vat(bank).frob(gilk, self, int(WAD), int(WAD));
        skip(1);
        Vat(bank).drip(gilk);

        // rest should be (fee - RAY) * WAD
        assertEq(Vat(bank).rest(), WAD);

        // wipe the urn...rest should be WAD + (WAD * (RAY + 1)) / RAY + 1
        // or iow the debt change minus the debt change rounded down by 1
        uint art = _art(gilk, self);
        Vat(bank).frob(gilk, self, int(0), -int(art));
        assertEq(Vat(bank).rest(), RAY);

        // rest is RAY (rest % RAY == 0), so should accumulate to joy
        skip(1);
        Vat(bank).drip(gilk);
        assertEq(Vat(bank).rest(), 0);
    }

    function test_drip_neg_fee() public {
        // can't set fee < RAY
        vm.expectRevert(Bank.ErrBound.selector);
        Vat(bank).filk(gilk, 'fee', bytes32(RAY / 2));

        // fees should be collected before changing fee
        Vat(bank).frob(gilk, self, int(100 * WAD), int(50 * WAD));
        skip(1);
        uint pre_joy = Vat(bank).joy();
        Vat(bank).filk(gilk, 'fee', bytes32(RAY));
        uint aft_joy = Vat(bank).joy();
        uint rake = aft_joy - pre_joy;
        assertGt(rake, 0);

        // fees should be based on previous rate rather than new
        skip(10);
        pre_joy = Vat(bank).joy();
        Vat(bank).filk(gilk, 'fee', bytes32(Vat(bank).FEE_MAX()));
        aft_joy = Vat(bank).joy();
        rake = aft_joy - pre_joy;
        // previous rate was RAY (zero fees)
        assertEq(rake, 0);
    }

    function test_feed_plot_safe() public {
        (Vat.Spot safe0,,) = Vat(bank).safe(gilk, self);
        assertEq(uint(safe0), uint(Vat.Spot.Safe));

        Vat(bank).frob(gilk, self, int(100 * WAD), int(50 * WAD));

        (Vat.Spot safe1,,) = Vat(bank).safe(gilk, self);
        assertEq(uint(safe1), uint(Vat.Spot.Safe));

        uint ink = _ink(gilk, self);
        uint art = _art(gilk, self);
        assertEq(ink, 100 * WAD);
        assertEq(art, 50 * WAD);

        // push same price, should still be safe
        feedpush(grtag, bytes32(RAY), block.timestamp + 1000);
        (Vat.Spot safe2,,) = Vat(bank).safe(gilk, self);
        assertEq(uint(safe2), uint(Vat.Spot.Safe));

        // price x0.02 -> should be unsafe
        feedpush(grtag, bytes32(RAY / 50), block.timestamp + 1000);
        (Vat.Spot safe3,,) = Vat(bank).safe(gilk, self);
        assertEq(uint(safe3), uint(Vat.Spot.Sunk));
    }

    function test_par() public {
        assertEq(Vat(bank).par(), RAY);
        Vat(bank).frob(gilk, self, int(100 * WAD), int(50 * WAD));
        (Vat.Spot spot,,) = Vat(bank).safe(gilk, self);
        assertEq(uint(spot), uint(Vat.Spot.Safe));

        // par increase should increase collateral requirement
        // -> urn sinks
        File(bank).file('par', bytes32(RAY * 3));
        (Vat.Spot spot2,,) = Vat(bank).safe(gilk, self);
        assertEq(uint(spot2), uint(Vat.Spot.Sunk));
    }

    function test_frob_err_ordering_1() public {
        // high fee, low ceil, medium dust
        Vat(bank).filk(gilk, 'fee', bytes32(FEE_2X_ANN));
        File(bank).file('ceil', bytes32(WAD - 1));
        Vat(bank).filk(gilk, 'dust', bytes32(RAD));

        // accumulate pending fees
        skip(BANKYEAR);
        Vat(bank).drip(gilk);

        // ceily, not safe, wrong urn, dusty...should be wrong urn
        feedpush(grtag, bytes32(0), type(uint).max);
        vm.expectRevert(Bank.ErrWrongUrn.selector);
        Vat(bank).frob(gilk, bank, int(WAD), int(WAD / 2));

        // right urn, should be unsafe
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(gilk, self, int(WAD), int(WAD / 2 - 1));

        // safe, should be dusty
        feedpush(grtag, bytes32(RAY * 100), type(uint).max);
        vm.expectRevert(Vat.ErrUrnDust.selector);
        Vat(bank).frob(gilk, self, int(WAD), int(WAD / 2 - 1));

        //non-dusty, should be ceily
        vm.expectRevert(Vat.ErrDebtCeil.selector);
        Vat(bank).frob(gilk, self, int(WAD), int((WAD + WAD / 1_000) / 2 ));

        // raising ceil should fix ceilyness
        File(bank).file('ceil', bytes32(WAD + WAD / 1_000));
        Vat(bank).frob(gilk, self, int(WAD), int((WAD + WAD / 10_000) / 2 ));
    }

    function test_frob_err_ordering_darts() public {
        // low ceil, medium dust
        File(bank).file('ceil', bytes32(WAD));
        Vat(bank).filk(gilk, 'dust', bytes32(RAD));
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);

        // check how it works with some fees dripped
        Vat(bank).filk(gilk, 'fee', bytes32(Vat(bank).FEE_MAX()));
        skip(1);
        Vat(bank).drip(gilk);

        // frob while pranking fsrc address
        gold.mint(fsrc, 1000 * WAD);
        vm.startPrank(fsrc);
        gold.approve(bank, 1000 * WAD);
        Vat(bank).frob(gilk, fsrc, int(WAD * 2), int(1 + WAD * RAY / Vat(bank).FEE_MAX()));

        // send the rico back to self
        rico.transfer(self, 100);
        vm.stopPrank();

        // bypasses most checks when dart <= 0
        feedpush(grtag, bytes32(0), type(uint).max);
        File(bank).file('ceil', bytes32(0));

        // can't help because dust
        vm.expectRevert(Vat.ErrUrnDust.selector);
        Vat(bank).frob(gilk, fsrc, int(WAD), -int(1));

        // can't hurt because permissions
        vm.expectRevert(Bank.ErrWrongUrn.selector);
        Vat(bank).frob(gilk, fsrc, int(WAD), int(1));

        // ok now frob my own urn...but it's not safe
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(gilk, self, int(WAD), int(1));

        // make it safe...should be dusty
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        vm.expectRevert(Vat.ErrUrnDust.selector);
        Vat(bank).frob(gilk, self, int(WAD), int(1));

        // frob a non-dusty amount...but fsrc already frobbed a bunch
        // should exceed ceil
        vm.expectRevert(Vat.ErrDebtCeil.selector);
        Vat(bank).frob(gilk, self, int(WAD), int(WAD));

        // ceiling checks are last
        File(bank).file('ceil', bytes32(WAD * 4));
        Vat(bank).frob(gilk, self, int(WAD), int(WAD));
    }

    function test_frob_err_ordering_dinks_1() public {
        // high fee, low ceil, medium dust
        Vat(bank).filk(gilk, 'fee', bytes32(FEE_2X_ANN));
        File(bank).file('ceil', bytes32(WAD));
        Vat(bank).filk(gilk, 'dust', bytes32(RAD));

        // accumulate pending fees
        skip(1);
        Vat(bank).drip(gilk);

        // gold:ref price 1k
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        gold.mint(fsrc, 1000 * WAD);

        // frob from fsrc address
        // could prank any non-self address, just chose fsrc's
        vm.startPrank(fsrc);
        gold.approve(bank, 1000 * WAD);
        Vat(bank).frob(gilk, fsrc, int(WAD * 2), int(1 + WAD * RAY / FEE_2X_ANN));
        vm.stopPrank();

        // bypasses some checks when dink >= 0 and dart <= 0
        feedpush(grtag, bytes32(0), type(uint).max);
        File(bank).file('ceil', bytes32(0));

        // self removes some ink from fsrc - should fail because unauthorized
        vm.expectRevert(Bank.ErrWrongUrn.selector);
        Vat(bank).frob(gilk, fsrc, -int(1), int(0));

        // fsrc removes some ink from fsrc - should fail because not safe
        vm.prank(fsrc);
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(gilk, fsrc, -int(1), int(0));

        // ...but it's fine when dink >= 0
        Vat(bank).frob(gilk, fsrc, int(0), int(0));
        Vat(bank).frob(gilk, fsrc, int(1), int(0));
    }

    function test_frob_err_ordering_dinks_darts() public {
        // high fee, high ceil, medium dust
        Vat(bank).filk(gilk, 'fee', bytes32(FEE_2X_ANN));
        File(bank).file('ceil', bytes32(WAD * 10000));
        Vat(bank).filk(gilk, 'dust', bytes32(RAD));

        // accumulate pending fees
        skip(1);
        Vat(bank).drip(gilk);

        // gold:ref price 1k
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        gold.mint(fsrc, 1000 * WAD);

        // could prank anything non-self; chose fsrc
        vm.startPrank(fsrc);
        gold.approve(bank, 1000 * WAD);
        Vat(bank).frob(gilk, fsrc, int(WAD * 2), int(1 + WAD * RAY / FEE_2X_ANN));

        // 2 for accumulated debt, 1 for rounding
        rico.transfer(self, 3);
        vm.stopPrank();

        // bypasses some checks when dink >= 0 and dart <= 0
        feedpush(grtag, bytes32(0), type(uint).max);
        File(bank).file('ceil', bytes32(WAD * 10000));

        // can't steal ink from someone else's urn
        vm.expectRevert(Bank.ErrWrongUrn.selector);
        Vat(bank).frob(gilk, fsrc, -int(1), int(1));

        // ...can remove ink from your own, but it has to be safe
        vm.prank(fsrc);
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(gilk, fsrc, -int(1), int(1));

        // set gold price so it's safe
        // nothing wrong with frobbing 0
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        Vat(bank).frob(gilk, fsrc, int(0), int(0));

        // can't reduce debt below dust
        vm.expectRevert(Vat.ErrUrnDust.selector);
        Vat(bank).frob(gilk, fsrc, int(1), int(-1));

        // ...raise dust - now it's fine
        Vat(bank).filk(gilk, 'dust', bytes32(RAD / 2));
        Vat(bank).frob(gilk, fsrc, int(1), int(-1));
    }

    function test_frob_ilk_uninitialized() public {
        vm.expectRevert(Vat.ErrIlkInit.selector);
        Vat(bank).frob('hello', self, int(WAD), int(WAD));
    }

    function test_debt_not_normalized() public {
        // accumulate pending fees, then set fee high
        Vat(bank).drip(gilk);
        Vat(bank).filk(gilk, 'fee', bytes32(Vat(bank).FEE_MAX()));

        // rack == 1, so debt should increase by dart
        Vat(bank).frob(gilk, self, int(WAD), int(WAD));
        assertEq(Vat(bank).debt(), WAD);

        // if drip 10X rack, it should (roughly) 10X debt
        skip(BANKYEAR);
        Vat(bank).drip(gilk);
        assertClose(Vat(bank).debt(), WAD * 10, 1_000_000_000);
    }

    function test_dtab_not_normalized() public {
        // gold:ref price 1k
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);

        // accumulate pending fees, then set fee high
        Vat(bank).drip(gilk);
        Vat(bank).filk(gilk, 'fee', bytes32(FEE_2X_ANN));

        // rack is 0, so debt should increase by dart
        Vat(bank).frob(gilk, self, int(WAD), int(WAD));
        assertEq(Vat(bank).debt(), WAD);

        skip(BANKYEAR);
        Vat(bank).drip(gilk);

        // dart > 0, so dtab > 0
        // dart == 1, rack == 2, so dtab should be 2
        uint ricobefore = rico.balanceOf(self);
        Vat(bank).frob(gilk, self, int(WAD), int(WAD));
        uint ricoafter  = rico.balanceOf(self);
        assertClose(ricoafter, ricobefore + WAD * 2, 1_000_000);

        // dart < 0 -> dtab < 0
        // dart == -1, rack == 2 -> dtab should be -2
        // minus some change for rounding
        ricobefore = rico.balanceOf(self);
        Vat(bank).frob(gilk, self, int(0), -int(WAD));
        ricoafter = rico.balanceOf(self);
        assertClose(ricoafter, ricobefore - (WAD * 2 + 1), 1_000_000);
    }

    function test_drip_all_rest_1() public {
        // gold:ref price 1k
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        Vat(bank).filk(gilk, 'fee', bytes32(FEE_1_5X_ANN));

        // raise rack to 1.5
        skip(BANKYEAR);
        // now frob 1, so debt is 1
        // and rest is 0.5 * RAY
        Vat(bank).drip(gilk);
        Vat(bank).frob(gilk, self, int(1), int(1));
        assertClose(Vat(bank).rest(), RAY / 2, 1_000_000);
        assertEq(Vat(bank).debt(), 1);
        // need to wait for drip to do anything...
        Vat(bank).drip(gilk);
        assertEq(Vat(bank).debt(), 1);
        assertClose(Vat(bank).rest(), RAY / 2, 1_000_000);

        // frob again so rest reaches RAY
        Vat(bank).frob(gilk, self, int(1), int(1));
        assertEq(Vat(bank).debt(), 2);
        assertClose(Vat(bank).rest(), RAY, 1_000_000);

        // so regardless of fee next drip should drip 1 (== rest / RAY)
        Vat(bank).filk(gilk, 'fee', bytes32(RAY));
        skip(1);
        Vat(bank).drip(gilk);

        assertEq(Vat(bank).debt(), 3);
        assertLt(Vat(bank).rest(), RAY / 1_000_000);
        assertEq(rico.totalSupply(), 2);
        assertEq(Vat(bank).joy(), 1);
        assertEq(Vat(bank).joy() + rico.totalSupply(), Vat(bank).debt());
    }

    function test_get() public {
        bytes32 val = Vat(bank).get(gilk, 'src');
        assertEq(address(bytes20(val)), fsrc);

        val = Vat(bank).get(gilk, 'tag');
        assertEq(val, grtag);

        vm.expectRevert(Bank.ErrWrongKey.selector);
        Vat(bank).get(gilk, 'oh');
    }

    function test_filk() public {
        bytes32 val = Vat(bank).get(gilk, 'src');
        assertEq(address(bytes20(val)), fsrc);
        Vat(bank).filk(gilk, 'src', bytes32(bytes20(0)));

        val = Vat(bank).get(gilk, 'src');
        assertEq(address(bytes20(val)), address(0));

        // wrong key
        vm.expectRevert(Bank.ErrWrongKey.selector);
        Vat(bank).filk(gilk, 'ok', bytes32(bytes20(self)));
    }

    function test_bail_drips() public {
        // gold:ref price 1k
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        Vat(bank).frob(gilk, self, int(WAD), int(WAD));

        // accrue fees for a year
        skip(BANKYEAR);

        // bail should accumulate pending fees before liquidating
        // -> bail should update rack
        feedpush(grtag, bytes32(0), type(uint).max);
        uint prevrack = Vat(bank).ilks(gilk).rack;
        Vat(bank).bail(gilk, self);
        assertGt(Vat(bank).ilks(gilk).rack, prevrack);
    }

    // make sure bailed ink decodes properly
    function test_bail_return_value() public {
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        Vat(bank).frob(gilk, self, int(WAD), int(WAD));
        feedpush(grtag, bytes32(0), type(uint).max);
        uint sold = Vat(bank).bail(gilk, self);
        assertEq(sold, WAD);
    }

    function test_ink_return_value() public {
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        Vat(bank).frob(gilk, self, int(WAD), int(WAD));
        uint ink = _ink(gilk, self);
        assertEq(ink, WAD);
    }

    function test_ceil_big_rest() public {
        // frob a billion rico
        // simple way to quickly generate some rest
        gold.mint(self, RAY * 1000);
        File(bank).file('ceil', bytes32(RAY));
        Vat(bank).filk(gilk, 'line', bytes32(UINT256_MAX));

        // gold:ref price 1k
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);

        // accumulate pending fees
        skip(1);
        Vat(bank).drip(gilk);
        // now - tau == 0, so rack should be unchanged
        assertGt(Vat(bank).ilks(gilk).rack, RAY);

        Vat(bank).frob(gilk, self, int(RAY), int(RAY * 2 / 3));

        // make about 50 * RAY rest to exceed ceil while debt < ceil
        for (uint i = 0; i < 100; i++) {
            int dart = i % 2 == 0 ? -int(RAY / 2): int(RAY / 2);
            Vat(bank).frob(gilk, self, int(0), dart);
        }

        // frob what space is left below ceil
        // ceiling check should take rest into account
        uint diff = Vat(bank).ceil() - Vat(bank).debt();
        uint rack = Vat(bank).ilks(gilk).rack;
        vm.expectRevert(Vat.ErrDebtCeil.selector);
        Vat(bank).frob(gilk, self, int(0), int(rdiv(diff, rack)));

        skip(1);
        // drip to mod the rest so it's < RAY and recalculate dart
        // frob should work now
        Vat(bank).drip(gilk);
        diff = Vat(bank).ceil() - Vat(bank).debt();
        rack = Vat(bank).ilks(gilk).rack;
        Vat(bank).frob(gilk, self, int(0), int(rdiv(diff, rack)));
    }

    function test_bail_pop_pep() public {
        // set pep and pop to something awk
        uint pep = 3;
        uint pop = 5 * RAY;
        Vat(bank).filk(gilk, 'pep', bytes32(pep));
        Vat(bank).filk(gilk, 'pop', bytes32(pop));

        // gold:ref price 1
        feedpush(grtag, bytes32(RAY), UINT256_MAX);
        Vat(bank).frob(gilk, self, int(WAD), int(WAD));

        // make it very unsafe
        feedpush(grtag, bytes32(RAY / 6), UINT256_MAX);

        // bail should charge proportional to pop * underwater-ness ^ pop
        uint pre_rico = rico.balanceOf(self);
        Vat(bank).bail(gilk, self);
        uint aft_rico = rico.balanceOf(self);
        uint paid     = pre_rico - aft_rico;

        // liqr is 1.0 so 1/6 backed
        // Estimate amount paid, put in a wad of gold now priced at 1/6
        uint tot  = WAD / 6;
        uint rush = 6;
        uint est  = rmul(tot, pop) / rush**pep;

        assertClose(paid, est, 1000000000);
    }

    function test_bail_pop_pep_with_liqr() public {
        // set pep and pop to something awk
        uint pep  = 3;
        uint pop  = 5 * RAY;
        uint liqr = 2 * RAY;
        Vat(bank).filk(gilk, 'pep', bytes32(pep));
        Vat(bank).filk(gilk, 'pop', bytes32(pop));

        // gold:ref price 1
        feedpush(grtag, bytes32(RAY), UINT256_MAX);
        Vat(bank).frob(gilk, self, int(WAD), int(WAD));

        // set high liqr, low price
        Vat(bank).filk(gilk, 'liqr', bytes32(liqr));
        feedpush(grtag, bytes32(RAY / 6), UINT256_MAX);

        // liqr, price, pep and pop should all affect bail revenue
        uint pre_rico = rico.balanceOf(self);
        Vat(bank).bail(gilk, self);
        uint aft_rico = rico.balanceOf(self);
        uint paid     = pre_rico - aft_rico;

        // liqr is 2.0 so deal should be 1 / 12
        uint tot  = WAD / 6;
        uint rush = 12;
        uint est  = rmul(tot, pop) / rush**pep;

        assertClose(paid, est, 1000000000);
    }

    function test_deal_but_not_wild() public {
        // gold:ref price 1
        feedpush(grtag, bytes32(RAY), UINT256_MAX);
        Vat(bank).frob(gilk, self, int(WAD), int(WAD));

        // simulate an intense (but feasible) price crash
        // gold:ref price 0.000001
        feedpush(grtag, bytes32(RAY / 1_000_000), UINT256_MAX);
        Vat(bank).filk(gilk, 'pep', bytes32(uint(4)));

        // shouldn't cause an overflow in deal/earn calc
        Vat(bank).bail(gilk, self);
    }

    function test_frob_safer_over_ceilings() public {
        // should be able to pay down urns that are over ceiling
        Vat(bank).frob(gilk, self, int(2000 * WAD), int(1000 * WAD));

        // over line, under ceil
        Vat(bank).filk(gilk, 'line', bytes32(0));

        // safer dart
        Vat(bank).frob(gilk, self, int(0), -int(WAD));

        // safer dink (hook property - vat doesn't care)
        Vat(bank).frob(gilk, self, int(WAD), 0);

        // safer dart and dink
        Vat(bank).frob(gilk, self, int(WAD), -int(WAD));

        // under line, over ceil
        Vat(bank).filk(gilk, 'line', bytes32(UINT256_MAX));
        File(bank).file('ceil', bytes32(0));
        Vat(bank).frob(gilk, self, int(0), -int(WAD));
        Vat(bank).frob(gilk, self, int(WAD), 0);

        // under line, under ceil
        Vat(bank).filk(gilk, 'line', bytes32(UINT256_MAX));
        File(bank).file('ceil', bytes32(UINT256_MAX));
        Vat(bank).frob(gilk, self, int(0), -int(WAD));
        Vat(bank).frob(gilk, self, int(WAD), 0);
    }

    function test_wipe_not_safer_over_ceilings() public {
        Vat(bank).frob(gilk, self, int(2000 * WAD), int(1000 * WAD));

        File(bank).file('ceil', bytes32(0));
        Vat(bank).filk(gilk, 'line', bytes32(0));

        // shouldn't do ceiling check on wipe,
        // even if frob makes CDP less safe
        Vat(bank).frob(gilk, self, -int(WAD), -int(WAD));
    }

    function test_bail_moves_line() public {
        // defensive line
        uint dink   = WAD * 1000;
        uint borrow = WAD * 1000;
        uint line0  = RAD * 1000;

        // set some semi-normal values for line liqr pep pop
        // doesn't matter too much, this test just cares about change in sin
        Vat(bank).filk(gilk, 'line', bytes32(line0));
        Vat(bank).filk(gilk, "liqr", bytes32(RAY));
        Vat(bank).filk(gilk, "pep",  bytes32(uint(1)));
        Vat(bank).filk(gilk, "pop",  bytes32(RAY));

        // gold:ref price 1
        feedpush(grtag, bytes32(RAY), type(uint).max);

        // frob to edge of safety and line
        Vat(bank).frob(gilk, self, int(dink), int(borrow));

        // halve gold:ref price
        feedpush(grtag, bytes32(RAY / 2), type(uint).max);

        uint sr0   = rico.balanceOf(self);
        uint sg0   = gold.balanceOf(self);
        Vat(bank).bail(gilk, self);
        uint line1 = Vat(bank).ilks(gilk).line;
        uint sr1   = rico.balanceOf(self);
        uint sg1   = gold.balanceOf(self);

        // was initially at limits of line and art, and price dropped to half
        // rico recovery will be borrowed amount * 0.5 for price, * 0.5 for deal
        // line should have decreased to 25% capacity
        assertEq(line0 / 4, line1);
        assertEq(sr0, sr1 + borrow / 4);
        assertEq(sg0, sg1 - dink);

        // line got defensive, so should be barely too low now
        vm.expectRevert(Vat.ErrDebtCeil.selector);
        Vat(bank).frob(gilk, self, int(dink), int(borrow / 4 + 1));
        // barely under line
        Vat(bank).frob(gilk, self, int(dink), int(borrow / 4));

        // set really low line to test defensive line underflow
        Vat(bank).filk(gilk, 'line', bytes32(line0 / 10));

        // another big gold dip, then bail
        feedpush(grtag, bytes32(RAY / 10), type(uint).max);
        Vat(bank).bail(gilk, self);

        // fees or line modifications can lead to loss > capacity, check no underflow
        uint line2 = Vat(bank).ilks(gilk).line;
        assertEq(line2, 0);
    }

    function test_no_drip_uninitialized_ilk() public {
        vm.expectRevert(Vat.ErrIlkInit.selector);
        Vat(bank).drip('hello');
    }

    function test_no_bail_unitialized_ilk() public {
        vm.expectRevert(Vat.ErrIlkInit.selector);
        Vat(bank).bail('hello', self);
    }

    // test behavior when transfer/transferFrom returns false
    function test_ErrTransfer() public {
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        FalseGem fgem = new FalseGem();

        // fgem doesn't revert but always returns false.  Should fail
        Vat(bank).filk(gilk, 'gem', bytes32(bytes20(address(fgem))));
        vm.expectRevert(Vat.ErrTransfer.selector);
        Vat(bank).frob(gilk, self, int(WAD), int(WAD));

        // lock some gold (don't really need to but just for niceness)
        Vat(bank).filk(gilk, 'gem', bytes32(bytes20(agold)));
        Vat(bank).frob(gilk, self, int(WAD), int(WAD));

        // switch back and try to free some gem.  should fail bc returns false
        Vat(bank).filk(gilk, 'gem', bytes32(bytes20(address(fgem))));
        vm.expectRevert(Vat.ErrTransfer.selector);
        Vat(bank).frob(gilk, self, -int(WAD / 2), 0);
    }

    function test_bel_when_bail_recoups_losses() public {
        Vat(bank).filk(gilk, 'fee', bytes32(RAY));
        File(bank).file('bel', bytes32(block.timestamp));

        skip(1);

        assertEq(Vat(bank).joy(), Vat(bank).sin() / RAY);

        // little bit of joy, so pre-bailhook deficit and post-bailhook surplus
        // WAD / 10 joy, 0 sin -> call bail -> WAD / 10 joy, RAD sin
        // -> call bailhook -> WAD / 10 + WAD * (99 / 100) ** 2 joy, RAD sin
        //
        // ensures that bel update comes after bailhook
        force_fees(WAD / 10);
        rico_mint(WAD, false);
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        Vat(bank).frob(gilk, self, int(WAD), int(WAD));

        feedpush(grtag, bytes32(RAY * 99 / 100), type(uint).max);
        Vat(bank).bail(gilk, self);

        assertEq(Vow(bank).ramp().bel, block.timestamp - 1);
    }

}

contract FalseGem {
    uint count;
    function transferFrom(address,address,uint) external returns (bool) {
        count++;
        return false;
    }
    function transfer(address,uint) external returns (bool) {
        count++;
        return false;
    }
}
