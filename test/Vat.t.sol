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
    address constant fakesrc = 0xF33df33dF33dF33df33df33df33dF33DF33Df33D;

    address[] gems;
    uint256[] wads;

    function setUp() public {
        make_bank();
        init_risk();
        risk.mint(bank, init_join * WAD);

        // non-self user
        guy = new Guy(bank);
    }

    function test_frob_basic() public {
        Vat(bank).frob(rilk, self, int(WAD), int(WAD));
        Vat(bank).frob(rilk, self, int(WAD), int(WAD));
    }

    function test_drip_basic() public {
        // set fee to something >1 so joy changes
        Vat(bank).drip(rilk);
        Vat(bank).filk(rilk, 'fee', bytes32(FEE_2X_ANN));

        skip(1);

        // frob retroactively, drip the profits
        Vat(bank).frob(rilk, self, int(100 * WAD), int(50 * WAD));
        Vat(bank).drip(rilk);
    }

    function test_ilk_reset() public {
        // can't set an ilk twice
        vm.expectRevert(Vat.ErrMultiIlk.selector);
        Vat(bank).init(rilk);
    }

    ///////////////////////////////////////////////
    // urn safety tests
    ///////////////////////////////////////////////

    // risk:ref, par, and liqr all = 1 after set up
    function test_create_unsafe() public {
        // art should not exceed ink, because price par liqr all == 1
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(rilk, address(this), int(stack), int(stack) + 1);
    }

    function test_safe_return_vals() public {
        Vat(bank).filk(rilk, 'fee', bytes32(FEE_2X_ANN));
        Vat(bank).frob(rilk, address(this), int(stack), int(stack));
        (uint deal, uint tot) = Vat(bank).safe(rilk, self);

        // position should be (barely) safe
        assertTrue(deal == RAY);

        // when safe deal should be 1
        assertEq(deal, RAY);

        // tot should be ink as a rad
        uint tot1 = stack * RAY;
        assertEq(tot, tot1);

        // accumulate fees to 2x...position should sink underwater
        skip(BANKYEAR);
        Vat(bank).drip(rilk);
        (deal, tot) = Vat(bank).safe(rilk, self);
        assertTrue(deal < RAY);

        // tab doubled, so deal halved
        assertClose(deal, RAY / 2, 10000000);
        // tot unchanged since it's just ink rad
        assertClose(tot, tot1, 10000000);

        // always safe if debt is zero
        rico_mint(1000 * WAD, true);
        Vat(bank).frob(rilk, address(this), int(0), - int(_art(rilk, self)));
        (deal, tot) = Vat(bank).safe(rilk, self);
        assertTrue(deal == RAY);
    }

    function test_rack_puts_urn_underwater() public {
        // frob till barely safe
        Vat(bank).frob(rilk, address(this), int(stack), int(stack));
        (uint deal,) = Vat(bank).safe(rilk, self);
        assertTrue(deal == RAY);

        // accrue some interest to sink
        skip(100);
        Vat(bank).drip(rilk);
        (deal,) = Vat(bank).safe(rilk, self);
        assertTrue(deal < RAY);

        // can't refloat using fee, because fee must be >=1
        vm.expectRevert(Bank.ErrBound.selector);
        Vat(bank).filk(rilk, 'fee', bytes32(RAY - 1));
    }

    function test_liqr_puts_urn_underwater() public {
        // frob till barely safe
        Vat(bank).frob(rilk, address(this), int(stack), int(stack));
        (uint deal,) = Vat(bank).safe(rilk, self);
        assertTrue(deal == RAY);

        // raise liqr a little bit...should sink the urn
        Vat(bank).filk(rilk, 'liqr', bytes32(RAY + 1000000));
        (deal,) = Vat(bank).safe(rilk, self);
        assertTrue(deal < RAY);

        // can't have liqr < 1
        vm.expectRevert(Bank.ErrBound.selector);
        Vat(bank).filk(rilk, 'liqr', bytes32(RAY - 1));

        // lower liqr back down...should refloat the urn
        Vat(bank).filk(rilk, 'liqr', bytes32(RAY));
        (deal,) = Vat(bank).safe(rilk, self);
        assertTrue(deal == RAY);
    }

    function test_frob_refloat() public {
        // frob till barely safe
        Vat(bank).frob(rilk, address(this), int(stack), int(stack));
        (uint deal,) = Vat(bank).safe(rilk, self);
        assertTrue(deal == RAY);

        // sink the urn
        skip(BANKYEAR);
        Vat(bank).drip(rilk);
        (deal,) = Vat(bank).safe(rilk, self);
        assertTrue(deal < RAY);

        // add ink to refloat
        Vat(bank).frob(rilk, address(this), int(stack), int(0));
        (deal,) = Vat(bank).safe(rilk, self);
        assertTrue(deal == RAY);
    }

    function test_increasing_risk_sunk_urn() public {
        // frob till barely safe
        Vat(bank).frob(rilk, address(this), int(stack), int(stack));
        (uint deal,) = Vat(bank).safe(rilk, self);
        assertTrue(deal == RAY);

        // sink it
        skip(BANKYEAR);
        Vat(bank).drip(rilk);
        (deal,) = Vat(bank).safe(rilk, self);
        assertTrue(deal < RAY);

        // should always be able to decrease art or increase ink, even when sunk
        Vat(bank).frob(rilk, address(this), int(0), int(-1));
        Vat(bank).frob(rilk, address(this), int(1), int(0));

        // should not be able to decrease ink or increase art of sunk urn
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(rilk, address(this), int(10), int(1));
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(rilk, address(this), int(-1), int(-1));
    }

    function test_increasing_risk_safe_urn() public {
        // frob till very safe
        Vat(bank).frob(rilk, address(this), int(stack), int(10));
        (uint deal,) = Vat(bank).safe(rilk, self);
        assertTrue(deal == RAY);

        // should always be able to decrease art or increase ink
        Vat(bank).frob(rilk, address(this), int(0), int(-1));
        Vat(bank).frob(rilk, address(this), int(1), int(0));

        // should be able to decrease ink or increase art of safe urn
        // as long as resulting urn is safe
        Vat(bank).frob(rilk, address(this), int(0), int(1));
        Vat(bank).frob(rilk, address(this), int(-1), int(0));
    }

    function test_basic_bail() public {
        Vat(bank).frob(rilk, self, int(WAD), int(WAD));
        skip(BANKYEAR);
        Vat(bank).bail(rilk, self);
    }

    function test_bail_price_1() public {
        // frob to edge of safety
        uint borrow = WAD * 1000;
        Vat(bank).filk(rilk, 'liqr', bytes32(RAY));
        Vat(bank).frob(rilk, self, int(borrow), int(borrow));

        // raise urn's debt to 1.5x original...pep is 2, so earn is cubic
        Vat(bank).filk(rilk, 'fee', bytes32(FEE_1_5X_ANN));
        skip(BANKYEAR);

        // (2/3)**2 for deal**pep, because tab ~= ink * 3 / 2
        uint expected = borrow * 2**2 / 3**2;
        rico_mint(expected, false);
        rico.transfer(address(guy), expected);
        uint earn = guy.bail(rilk, self);

        // return value is amount of risk received
        assertEq(earn, 1000 * WAD);

        // guy was given exact amount, check almost all was spent for all risk deposit
        assertLt(rico.balanceOf(address(guy)), WAD / 1000000);
        assertEq(risk.balanceOf(address(guy)), 1000 * WAD);
    }

    function test_bail_price_pup_1() public {
        // frob to edge of safety
        uint borrow = 1000 * WAD;

        uint pep = 1;
        uint pop = 2 * RAY;
        int  pup = -int(RAY);

        Vat(bank).filk(rilk, "pep", bytes32(pep));
        Vat(bank).filk(rilk, "pop", bytes32(pop));
        Vat(bank).filk(rilk, "pup", bytes32(uint(pup)));
        Vat(bank).filk(rilk, "fee", bytes32(FEE_1_5X_ANN));

        Vat(bank).frob(rilk, self, int(1000 * WAD), int(borrow));

        // drop ink/tab to 66%...pep is 1, so earn is linear
        skip(BANKYEAR);
        uint expected = rmul(borrow, rmash(RAY * 2 / 3, pep, pop, pup));
        prepguyrico(expected, false);
        uint earn = guy.bail(rilk, self);
        // check returned bytes represent quantity of tokens received
        assertEq(earn, 1000 * WAD);

        // guy was given exact amount, check all was spent for all risk deposit
        assertLt(rico.balanceOf(address(guy)), WAD / 100000);
        assertEq(risk.balanceOf(address(guy)), 1000 * WAD);

        // clamping
        pep = 2; pop = 3 * RAY / 2; pup = -int(RAY / 8);
        Vat(bank).filk(rilk, "pep", bytes32(pep));
        Vat(bank).filk(rilk, "pop", bytes32(pop));
        Vat(bank).filk(rilk, "pup", bytes32(uint(pup)));

        // 2 * borrow because skipped bankyear
        risk.mint(self, 10000 * WAD);
        Vat(bank).frob(rilk, self, int(2 * borrow), int(borrow));

        // skip a bunch so mash clamps to 0
        skip(BANKYEAR * 10);

        // should give all ink, shouldn't cost any rico
        assertEq(guy.bail(rilk, self), 2 * borrow);
        assertLt(rico.balanceOf(address(guy)), WAD / 100000);
    }

    function test_bail_refund() public {
        // set c ratio to double
        uint pop = RAY * 3 / 2;
        uint pep = 2;
        uint borrow = WAD * 500;
        uint dink = borrow * 5 / 2;
        Vat(bank).filk(rilk, "liqr", bytes32(RAY * 2));
        Vat(bank).filk(rilk, "pep",  bytes32(pep));
        Vat(bank).filk(rilk, "pop",  bytes32(pop));
        Vat(bank).filk(rilk, "fee",  bytes32(FEE_1_5X_ANN));

        // frob to edge of safety
        Vat(bank).frob(rilk, self, int(dink), int(borrow));

        // drop to 66%...position is still overcollateralized
        skip(BANKYEAR);

        // deal should be 0.66...still overcollateralized
        rico_mint(borrow, false);
        rico.transfer(address(guy), 3 * borrow * 2 / 3);

        uint deal = RAY * 5 / 2 * 2 / 3 / 2;
        uint mash = rmash(deal, pep, pop, 0);
        uint cost_unclamped = rmul(dink, mash);
        uint tab  = borrow * 3 / 2;
        guy.bail(rilk, self);

        // guy should not get all risk, as position was overcollateralized
        // guy gets ink * (borrowed / total ink value)
        uint guy_earn = rmul(dink, rdiv(tab, cost_unclamped));
        assertClose(risk.balanceOf(address(guy)), guy_earn, 1000000);

        // excess ink should be sent back to urn holder, not left in urn
        uint ink_left = _ink(rilk, self);
        assertClose(ink_left, dink - guy_earn, 1000000);
        assertGt(ink_left, 0);
    }


    //////////////////////////////////////////////////
    // join/exit tests
    //////////////////////////////////////////////////

    function test_rico_join_exit() public {
        uint self_risk_bal0 = risk.balanceOf(self);
        uint self_rico_bal0 = rico.balanceOf(self);

        // revert for trying to join more gems than owned
        vm.expectRevert(Gem.ErrUnderflow.selector);
        Vat(bank).frob(rilk, self, int(self_risk_bal0 + 1), 0);

        // revert for trying to exit too much rico
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(rilk, self, int(10), int(11));

        // revert for trying to exit gems from other users
        vm.expectRevert(Math.ErrUintUnder.selector);
        Vat(bank).frob(rilk, self, int(-1), 0);

        // gems are taken from user when joining, and rico given to user
        Vat(bank).frob(rilk, self, int(stack), int(stack / 2));
        uint self_risk_bal1 = risk.balanceOf(self);
        uint self_rico_bal1 = rico.balanceOf(self);
        assertEq(self_risk_bal1 + stack, self_risk_bal0);
        assertEq(self_rico_bal1, self_rico_bal0 + stack / 2);

        // close, even without drip need 1 extra rico as rounding is in systems favour
        rico_mint(1, false);
        Vat(bank).frob(rilk, self, -int(stack), -int(stack / 2));
        uint self_risk_bal2 = risk.balanceOf(self);
        uint self_rico_bal2 = rico.balanceOf(self);
        assertEq(self_risk_bal0, self_risk_bal2);
        assertEq(self_rico_bal0, self_rico_bal2);
    }

    function test_init_conditions() public view {
        assertEq(BankDiamond(bank).owner(), self);
    }

    function test_rejects_unsafe_frob() public {
        uint ink = _ink(rilk, self);
        uint art = _art(rilk, self);
        assertEq(ink, 0);
        assertEq(art, 0);

        // no collateral...shouldn't be able to borrow
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(rilk, self, int(0), int(WAD));
    }

    // amount of rico owed to pay down the CDP
    function owed() internal returns (uint) {
        // update rack first
        Vat(bank).drip(rilk);

        uint rack = Vat(bank).ilks(rilk).rack;
        uint art = _art(rilk, self);
        return rack * art;
    }

    function test_drip() public {
        // set a high fee
        Vat(bank).filk(rilk, 'fee', bytes32(Vat(bank).FEE_MAX()));

        // drip a little bit so this isn't the first fee accumulation
        skip(1);
        Vat(bank).drip(rilk);
        Vat(bank).frob(rilk, self, int(100 * WAD), int(50 * WAD));

        // wait a second, just so it's more realistic
        skip(1);
        uint debt0 = owed();

        skip(1);
        uint debt1 = owed();
        assertClose(debt1, rmul(debt0, Vat(bank).FEE_MAX()), 1_000_000_000_000);
    }

    function test_rest_monotonic() public {
        // set a tiny fee - will accumulate to rest
        Vat(bank).filk(rilk, 'fee', bytes32(RAY + 2));
        Vat(bank).filk(rilk, 'dust', bytes32(0));

        // frob a tiny bit more than a wad so lower bits of fee go to rest
        Vat(bank).frob(rilk, self, int(WAD + 1), int(WAD + 1));

        // drip to accumulate to rest
        skip(1);
        Vat(bank).drip(rilk);
        assertEq(Vat(bank).rest(), 2 * WAD + 2);

        // drip again, should have more rest now
        skip(1);
        Vat(bank).drip(rilk);
        assertGt(Vat(bank).rest(), 2 * WAD + 2);
    }

    function test_rest_drip_0() public {
        // set a tiny fee and frob
        Vat(bank).filk(rilk, 'fee', bytes32(RAY + 1));
        Vat(bank).frob(rilk, self, int(WAD), int(WAD));

        // didn't frob any fractional rico, so rest should be (fee - RAY) * WAD
        skip(1);
        Vat(bank).drip(rilk);
        assertEq(Vat(bank).rest(), WAD);

        // do it again, should double
        skip(1);
        Vat(bank).drip(rilk);
        assertEq(Vat(bank).rest(), 2 * WAD);

        // no more fee - rest should stop increasing
        Vat(bank).filk(rilk, 'fee', bytes32(RAY));
        skip(1);
        Vat(bank).drip(rilk);
        assertEq(Vat(bank).rest(), 2 * WAD);
    }

    function test_rest_drip_toggle_ones() public {
        // drip with no fees
        Vat(bank).filk(rilk, 'fee', bytes32(RAY));
        Vat(bank).filk(rilk, 'dust', bytes32(0));
        Vat(bank).drip(rilk);

        // mint 1 to deal with rounding
        // then lock 1 and wipe 1
        rico_mint(1, true);
        Vat(bank).frob(rilk, self, int(1), int(1));
        Vat(bank).frob(rilk, self, -int(1), -int(1));

        // rest from rounding should be RAD / WAD == RAY
        Vat(bank).drip(rilk);
        assertEq(Vat(bank).rest(), RAY);

        // dripping should clear rest
        skip(1);
        Vat(bank).drip(rilk);
        assertEq(Vat(bank).rest(), 0);
    }

    function test_rest_drip_toggle_wads() public {
        // drip with no fees
        Vat(bank).filk(rilk, 'fee', bytes32(RAY));
        Vat(bank).drip(rilk);

        // tiny fee, no dust
        Vat(bank).filk(rilk, 'fee', bytes32(RAY + 1));
        Vat(bank).filk(rilk, 'dust', bytes32(0));

        // mint 1 for rounding, then frob and drip
        rico_mint(1, true);
        Vat(bank).frob(rilk, self, int(WAD), int(WAD));
        skip(1);
        Vat(bank).drip(rilk);

        // rest should be (fee - RAY) * WAD
        assertEq(Vat(bank).rest(), WAD);

        // wipe the urn...rest should be WAD + (WAD * (RAY + 1)) / RAY + 1
        // or iow the debt change minus the debt change rounded down by 1
        uint art = _art(rilk, self);
        Vat(bank).frob(rilk, self, int(0), -int(art));
        assertEq(Vat(bank).rest(), RAY);

        // rest is RAY (rest % RAY == 0), so should accumulate to joy
        skip(1);
        Vat(bank).drip(rilk);
        assertEq(Vat(bank).rest(), 0);
    }

    function test_drip_neg_fee() public {
        // can't set fee < RAY
        vm.expectRevert(Bank.ErrBound.selector);
        Vat(bank).filk(rilk, 'fee', bytes32(RAY / 2));

        // fees should be collected before changing fee
        Vat(bank).frob(rilk, self, int(100 * WAD), int(50 * WAD));
        skip(1);
        uint pre_joy = Vat(bank).joy();
        Vat(bank).filk(rilk, 'fee', bytes32(RAY));
        uint aft_joy = Vat(bank).joy();
        uint rake = aft_joy - pre_joy;
        assertGt(rake, 0);

        // fees should be based on previous rate rather than new
        skip(10);
        pre_joy = Vat(bank).joy();
        Vat(bank).filk(rilk, 'fee', bytes32(Vat(bank).FEE_MAX()));
        aft_joy = Vat(bank).joy();
        rake = aft_joy - pre_joy;
        // previous rate was RAY (zero fees)
        assertEq(rake, 0);
    }

    function test_par() public {
        assertEq(Vat(bank).par(), RAY);
        Vat(bank).frob(rilk, self, int(100 * WAD), int(50 * WAD));
        (uint deal,) = Vat(bank).safe(rilk, self);
        assertEq(deal, RAY);

        // par increase should increase collateral requirement
        // -> urn sinks
        File(bank).file('par', bytes32(RAY * 3));
        (deal,) = Vat(bank).safe(rilk, self);
        assertLt(deal, RAY);
    }

    function test_frob_err_ordering_1() public {
        // high fee, low ceil, medium dust
        Vat(bank).filk(rilk, 'fee', bytes32(FEE_2X_ANN));
        File(bank).file('ceil', bytes32(WAD - 1));
        Vat(bank).filk(rilk, 'dust', bytes32(RAD));

        // accumulate pending fees
        skip(BANKYEAR);
        Vat(bank).drip(rilk);

        // ceily, not safe, wrong urn, dusty...should be wrong urn
        vm.expectRevert(Bank.ErrWrongUrn.selector);
        Vat(bank).frob(rilk, bank, int(WAD / 2), int(WAD / 2));

        // right urn, should be unsafe
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(rilk, self, int(WAD / 2), int(WAD / 2 - 1));

        // safe, should be dusty
        vm.expectRevert(Vat.ErrUrnDust.selector);
        Vat(bank).frob(rilk, self, int(2 * WAD), int(WAD / 2 - 1));

        //non-dusty, should be ceily
        vm.expectRevert(Vat.ErrDebtCeil.selector);
        Vat(bank).frob(rilk, self, int(2 * WAD), int((WAD + WAD / 1_000) / 2 ));

        // raising ceil should fix ceilyness
        File(bank).file('ceil', bytes32(WAD + WAD / 1_000));
        Vat(bank).frob(rilk, self, int(2 * WAD), int((WAD + WAD / 10_000) / 2 ));
    }

    function test_frob_err_ordering_darts() public {
        // low ceil, medium dust
        File(bank).file('ceil', bytes32(WAD));
        Vat(bank).filk(rilk, 'dust', bytes32(RAD));

        // check how it works with some fees dripped
        Vat(bank).filk(rilk, 'fee', bytes32(Vat(bank).FEE_MAX()));
        skip(1);
        Vat(bank).drip(rilk);

        // frob while pranking fakesrc address
        risk.mint(fakesrc, 1000 * WAD);
        vm.startPrank(fakesrc);
        risk.approve(bank, 1000 * WAD);
        Vat(bank).frob(rilk, fakesrc, int(WAD * 2), int(1 + WAD * RAY / Vat(bank).FEE_MAX()));

        // send the rico back to self
        rico.transfer(self, 100);
        vm.stopPrank();

        // bypasses most checks when dart <= 0
        File(bank).file('ceil', bytes32(0));

        // can't help because dust
        vm.expectRevert(Vat.ErrUrnDust.selector);
        Vat(bank).frob(rilk, fakesrc, int(0), -int(1));

        // can't hurt because permissions
        vm.expectRevert(Bank.ErrWrongUrn.selector);
        Vat(bank).frob(rilk, fakesrc, int(0), int(1));

        // ok now frob my own urn...but it's not safe
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(rilk, self, int(0), int(1));

        // make it safe...should be dusty
        vm.expectRevert(Vat.ErrUrnDust.selector);
        Vat(bank).frob(rilk, self, int(WAD), int(1));

        // frob a non-dusty amount...but fakesrc already frobbed a bunch
        // should exceed ceil
        vm.expectRevert(Vat.ErrDebtCeil.selector);
        Vat(bank).frob(rilk, self, int(100 * WAD), int(WAD));

        // ceiling checks are last
        File(bank).file('ceil', bytes32(WAD * 4));
        Vat(bank).frob(rilk, self, int(100 * WAD), int(WAD));
    }

    function test_frob_err_ordering_dinks_1() public {
        // high fee, low ceil, medium dust
        Vat(bank).filk(rilk, 'fee', bytes32(FEE_2X_ANN));
        File(bank).file('ceil', bytes32(WAD));
        Vat(bank).filk(rilk, 'dust', bytes32(RAD));

        // accumulate pending fees
        skip(1);
        Vat(bank).drip(rilk);

        risk.mint(fakesrc, 1000 * WAD);

        // frob from fakesrc address
        // could prank any non-self address, just chose fakesrc's
        vm.startPrank(fakesrc);
        risk.approve(bank, 1000 * WAD);
        Vat(bank).frob(rilk, fakesrc, int(WAD * 2), int(1 + WAD * RAY / FEE_2X_ANN));
        vm.stopPrank();

        // bypasses some checks when dink >= 0 and dart <= 0
        File(bank).file('ceil', bytes32(0));

        // self removes some ink from fakesrc - should fail because unauthorized
        vm.expectRevert(Bank.ErrWrongUrn.selector);
        Vat(bank).frob(rilk, fakesrc, -int(WAD), int(0));

        // fakesrc removes some ink from fakesrc - should fail because not safe
        vm.prank(fakesrc);
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(rilk, fakesrc, -int(WAD), int(0));

        // ...but it's fine when dink >= 0
        Vat(bank).frob(rilk, fakesrc, int(0), int(0));
        Vat(bank).frob(rilk, fakesrc, int(1), int(0));
    }

    function test_frob_err_ordering_dinks_darts() public {
        // high fee, high ceil, medium dust
        Vat(bank).filk(rilk, 'fee', bytes32(FEE_2X_ANN));
        File(bank).file('ceil', bytes32(WAD * 10000));
        Vat(bank).filk(rilk, 'dust', bytes32(RAD));

        // accumulate pending fees
        skip(1);
        Vat(bank).drip(rilk);

        risk.mint(fakesrc, 1000 * WAD);

        // could prank anything non-self; chose fakesrc
        vm.startPrank(fakesrc);
        risk.approve(bank, 1000 * WAD);
        Vat(bank).frob(rilk, fakesrc, int(WAD * 2), int(1 + WAD * RAY / FEE_2X_ANN));

        // 2 for accumulated debt, 1 for rounding
        rico.transfer(self, 3);
        vm.stopPrank();

        // bypasses some checks when dink >= 0 and dart <= 0
        File(bank).file('ceil', bytes32(WAD * 10000));

        // can't steal ink from someone else's urn
        vm.expectRevert(Bank.ErrWrongUrn.selector);
        Vat(bank).frob(rilk, fakesrc, -int(WAD), int(1));

        // ...can remove ink from your own, but it has to be safe
        vm.prank(fakesrc);
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(rilk, fakesrc, -int(WAD), int(1));

        // nothing wrong with frobbing 0
        Vat(bank).frob(rilk, fakesrc, int(0), int(0));

        // can't reduce debt below dust
        vm.expectRevert(Vat.ErrUrnDust.selector);
        Vat(bank).frob(rilk, fakesrc, int(1), int(-1));

        // ...raise dust - now it's fine
        Vat(bank).filk(rilk, 'dust', bytes32(RAD / 2));
        Vat(bank).frob(rilk, fakesrc, int(1), int(-1));
    }

    function test_frob_ilk_uninitialized() public {
        vm.expectRevert(Vat.ErrIlkInit.selector);
        Vat(bank).frob('hello', self, int(WAD), int(WAD));
    }

    function test_debt_not_normalized() public {
        // accumulate pending fees, then set fee high
        Vat(bank).drip(rilk);
        Vat(bank).filk(rilk, 'fee', bytes32(Vat(bank).FEE_MAX()));

        // rack == 1, so debt should increase by dart
        Vat(bank).frob(rilk, self, int(WAD), int(WAD));
        assertEq(Vat(bank).debt(), WAD);

        // if drip 10X rack, it should (roughly) 10X debt
        skip(BANKYEAR);
        Vat(bank).drip(rilk);
        assertClose(Vat(bank).debt(), WAD * 10, 1_000_000_000);
    }

    function test_dtab_not_normalized() public {
        // accumulate pending fees, then set fee high
        Vat(bank).drip(rilk);
        Vat(bank).filk(rilk, 'fee', bytes32(FEE_2X_ANN));

        // rack is 0, so debt should increase by dart
        Vat(bank).frob(rilk, self, int(100 * WAD), int(WAD));
        assertEq(Vat(bank).debt(), WAD);

        skip(BANKYEAR);
        Vat(bank).drip(rilk);

        // dart > 0, so dtab > 0
        // dart == 1, rack == 2, so dtab should be 2
        uint ricobefore = rico.balanceOf(self);
        Vat(bank).frob(rilk, self, int(WAD), int(WAD));
        uint ricoafter  = rico.balanceOf(self);
        assertClose(ricoafter, ricobefore + WAD * 2, 1_000_000);

        // dart < 0 -> dtab < 0
        // dart == -1, rack == 2 -> dtab should be -2
        // minus some change for rounding
        ricobefore = rico.balanceOf(self);
        Vat(bank).frob(rilk, self, int(0), -int(WAD));
        ricoafter = rico.balanceOf(self);
        assertClose(ricoafter, ricobefore - (WAD * 2 + 1), 1_000_000);
    }

    function test_drip_all_rest_1() public {
        Vat(bank).filk(rilk, 'fee', bytes32(FEE_1_5X_ANN));

        // raise rack to 1.5
        skip(BANKYEAR);
        // now frob 1, so debt is 1
        // and rest is 0.5 * RAY
        Vat(bank).drip(rilk);
        Vat(bank).frob(rilk, self, int(1000), int(1));
        assertClose(Vat(bank).rest(), RAY / 2, 1_000_000);
        assertEq(Vat(bank).debt(), 1);
        // need to wait for drip to do anything...
        Vat(bank).drip(rilk);
        assertEq(Vat(bank).debt(), 1);
        assertClose(Vat(bank).rest(), RAY / 2, 1_000_000);

        // frob again so rest reaches RAY
        Vat(bank).frob(rilk, self, int(1), int(1));
        assertEq(Vat(bank).debt(), 2);
        assertClose(Vat(bank).rest(), RAY, 1_000_000);

        // so regardless of fee next drip should drip 1 (== rest / RAY)
        Vat(bank).filk(rilk, 'fee', bytes32(RAY));
        skip(1);
        Vat(bank).drip(rilk);

        assertEq(Vat(bank).debt(), 3);
        assertLt(Vat(bank).rest(), RAY / 1_000_000);
        assertEq(rico.totalSupply(), 2);
        assertEq(Vat(bank).joy(), 1);
        assertEq(Vat(bank).joy() + rico.totalSupply(), Vat(bank).debt());
    }

    function test_filk() public {
        assertEq(uint(Vat(bank).get(rilk, 'pep')), 2);
        Vat(bank).filk(rilk, 'pep', bytes32(bytes20(0)));

        assertEq(Vat(bank).get(rilk, 'pep'), 0);

        // wrong key
        vm.expectRevert(Bank.ErrWrongKey.selector);
        Vat(bank).filk(rilk, 'ok', bytes32(bytes20(self)));
    }

    function test_bail_drips() public {
        Vat(bank).frob(rilk, self, int(WAD), int(WAD));

        // accrue fees for a year
        skip(BANKYEAR);

        // bail should accumulate pending fees before liquidating
        // -> bail should update rack
        uint prevrack = Vat(bank).ilks(rilk).rack;
        Vat(bank).bail(rilk, self);
        assertGt(Vat(bank).ilks(rilk).rack, prevrack);
    }

    // make sure bailed ink decodes properly
    function test_bail_return_value() public {
        Vat(bank).filk(rilk, 'fee', bytes32(FEE_2X_ANN));
        Vat(bank).frob(rilk, self, int(WAD), int(WAD));

        // skip a lot so no refund
        skip(BANKYEAR * 10);
        uint sold = Vat(bank).bail(rilk, self);
        assertEq(sold, WAD);
    }

    function test_ink_return_value() public {
        Vat(bank).frob(rilk, self, int(WAD), int(WAD));
        uint ink = _ink(rilk, self);
        assertEq(ink, WAD);
    }

    function test_ceil_big_rest() public {
        // frob a billion rico
        // simple way to quickly generate some rest
        risk.mint(self, RAY * 1000);
        File(bank).file('ceil', bytes32(RAY));
        Vat(bank).filk(rilk, 'line', bytes32(UINT256_MAX));

        // accumulate pending fees (none, because now - rho == 0)
        skip(1);
        Vat(bank).drip(rilk);
        assertGt(Vat(bank).ilks(rilk).rack, RAY);

        Vat(bank).frob(rilk, self, int(RAY), int(RAY * 2 / 3));

        // make about 50 * RAY rest to exceed ceil while debt < ceil
        for (uint i = 0; i < 100; i++) {
            int dart = i % 2 == 0 ? -int(RAY / 2): int(RAY / 2);
            Vat(bank).frob(rilk, self, int(0), dart);
        }

        // frob what space is left below ceil
        // ceiling check should take rest into account
        uint diff = Vat(bank).ceil() - Vat(bank).debt();
        uint rack = Vat(bank).ilks(rilk).rack;
        vm.expectRevert(Vat.ErrDebtCeil.selector);
        Vat(bank).frob(rilk, self, int(RAY), int(rdiv(diff, rack)));

        skip(1);
        // drip to mod the rest so it's < RAY and recalculate dart
        // frob should work now
        Vat(bank).drip(rilk);
        diff = Vat(bank).ceil() - Vat(bank).debt();
        rack = Vat(bank).ilks(rilk).rack;
        Vat(bank).frob(rilk, self, int(RAY), int(rdiv(diff, rack)));
    }

    function test_bail_pop_pep_1() public {
        // set pep and pop to something awk
        uint pep = 3;
        uint pop = 5 * RAY;
        Vat(bank).filk(rilk, 'pep', bytes32(pep));
        Vat(bank).filk(rilk, 'pop', bytes32(pop));
        Vat(bank).filk(rilk, 'fee', bytes32(FEE_2X_ANN));

        Vat(bank).frob(rilk, self, int(WAD), int(WAD));

        // make it very unsafe
        skip(3 * BANKYEAR);

        // bail should charge proportional to pop * underwater-ness ^ pop
        uint pre_rico = rico.balanceOf(self);
        Vat(bank).bail(rilk, self);
        uint aft_rico = rico.balanceOf(self);
        uint paid     = pre_rico - aft_rico;

        // liqr is 1.0 so 1/8 backed
        // Estimate amount paid, put in a wad of risk now priced at 1/6
        uint tot  = WAD;
        uint deal = RAY / 8;
        uint mash = rmash(deal, pep, pop, 0);
        uint est  = rmul(tot, mash);

        assertClose(paid, est, 1000000);
    }

    function test_bail_pop_pep_with_liqr() public {
        // set pep and pop to something awk
        uint pep  = 3;
        uint pop  = 5 * RAY;
        uint liqr = 2 * RAY;
        Vat(bank).filk(rilk, 'pep', bytes32(pep));
        Vat(bank).filk(rilk, 'pop', bytes32(pop));
        Vat(bank).filk(rilk, 'fee', bytes32(FEE_2X_ANN));

        Vat(bank).frob(rilk, self, int(WAD), int(WAD));

        // set high liqr, low price
        Vat(bank).filk(rilk, 'liqr', bytes32(liqr));

        skip(4 * BANKYEAR);

        // liqr, price, pep and pop should all affect bail revenue
        uint pre_rico = rico.balanceOf(self);
        Vat(bank).bail(rilk, self);
        uint aft_rico = rico.balanceOf(self);
        uint paid     = pre_rico - aft_rico;

        // liqr is 2.0 so deal should be 1 / 32
        uint tot  = WAD;
        uint deal = RAY / 32;
        uint mash = rmash(deal, pep, pop, 0);
        uint est  = rmul(tot, mash);

        assertClose(paid, est, 1000000);
    }

    function test_deal_but_not_wild() public {
        Vat(bank).frob(rilk, self, int(WAD), int(WAD));

        Vat(bank).filk(rilk, 'pep', bytes32(uint(4)));

        // a lot of (feasible) accumulated fees
        Vat(bank).filk(rilk, 'fee', bytes32(FEE_2X_ANN));
        skip(BANKYEAR * 5);

        // shouldn't cause an overflow in deal/earn calc
        Vat(bank).bail(rilk, self);
    }

    function test_frob_safer_over_ceilings() public {
        // should be able to pay down urns that are over ceiling
        Vat(bank).frob(rilk, self, int(2000 * WAD), int(1000 * WAD));

        // over line, under ceil
        Vat(bank).filk(rilk, 'line', bytes32(0));

        // safer dart
        Vat(bank).frob(rilk, self, int(0), -int(WAD));

        // safer dink (hook property - vat doesn't care)
        Vat(bank).frob(rilk, self, int(WAD), 0);

        // safer dart and dink
        Vat(bank).frob(rilk, self, int(WAD), -int(WAD));

        // under line, over ceil
        Vat(bank).filk(rilk, 'line', bytes32(UINT256_MAX));
        File(bank).file('ceil', bytes32(0));
        Vat(bank).frob(rilk, self, int(0), -int(WAD));
        Vat(bank).frob(rilk, self, int(WAD), 0);

        // under line, under ceil
        Vat(bank).filk(rilk, 'line', bytes32(UINT256_MAX));
        File(bank).file('ceil', bytes32(UINT256_MAX));
        Vat(bank).frob(rilk, self, int(0), -int(WAD));
        Vat(bank).frob(rilk, self, int(WAD), 0);
    }

    function test_wipe_not_safer_over_ceilings() public {
        Vat(bank).frob(rilk, self, int(2000 * WAD), int(1000 * WAD));

        File(bank).file('ceil', bytes32(0));
        Vat(bank).filk(rilk, 'line', bytes32(0));

        // shouldn't do ceiling check on wipe,
        // even if frob makes CDP less safe
        Vat(bank).frob(rilk, self, -int(WAD), -int(WAD));
    }

    function test_bail_moves_line() public {
        // defensive line
        uint dink   = WAD * 500;
        uint borrow = WAD * 500;
        uint line0  = RAD * 1000;

        // set some semi-normal values for line liqr pep pop
        // doesn't matter too much, this test just cares about change in sin
        Vat(bank).filk(rilk, 'line', bytes32(line0));
        Vat(bank).filk(rilk, "liqr", bytes32(RAY));
        Vat(bank).filk(rilk, "pep",  bytes32(uint(1)));
        Vat(bank).filk(rilk, "pop",  bytes32(RAY));
        Vat(bank).filk(rilk, "fee",  bytes32(FEE_2X_ANN));


        // frob to edge of safety and line (pending year wait)
        Vat(bank).frob(rilk, self, int(dink), int(borrow));

        // double tab
        skip(BANKYEAR);

        uint sr0   = rico.balanceOf(self);
        uint sg0   = risk.balanceOf(self);
        Vat(bank).bail(rilk, self);
        uint line1 = Vat(bank).ilks(rilk).line;
        uint sr1   = rico.balanceOf(self);
        uint sg1   = risk.balanceOf(self);

        // rico recovery will be borrowed amount * 0.5 for ink/tab * 0.5 for deal
        // line should have decreased to 50% capacity
        assertClose(line0 / 4, line1, 10000);
        assertClose(sr0, sr1 + borrow * 2 / 4, 10000);
        assertEq(sg0, sg1 - dink);

        // line got defensive, so should be barely too low now
        vm.expectRevert(Vat.ErrDebtCeil.selector);
        Vat(bank).frob(rilk, self, int(dink), int(borrow / 4 * 100001 / 100000));
        // barely under line
        Vat(bank).frob(rilk, self, int(dink), int(borrow / 4));

        // set really low line to test defensive line underflow
        Vat(bank).filk(rilk, 'line', bytes32(line0 / 10));

        // another big fee accumulation, then bail
        skip(2 * BANKYEAR);
        Vat(bank).bail(rilk, self);

        // fees or line modifications can lead to loss > capacity, check no underflow
        uint line2 = Vat(bank).ilks(rilk).line;
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
