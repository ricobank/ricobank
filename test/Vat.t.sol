// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.25;

import "forge-std/Test.sol";

import { RicoSetUp, Guy } from "./RicoHelper.sol";
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
        risk_mint(abank, init_join * WAD);

        // non-self user
        guy = new Guy(bank);
    }

    function test_frob_basic() public {
        bank.frob(self, int(WAD), int(WAD));
        bank.frob(self, int(WAD), int(WAD));
    }

    function test_drip_basic() public {
        // set fee to something >1 so joy changes
        bank.drip();
        file('fee', bytes32(FEE_2X_ANN));

        skip(1);

        // frob retroactively, drip the profits
        bank.frob(self, int(100 * WAD), int(50 * WAD));
        bank.drip();
    }

    ///////////////////////////////////////////////
    // urn safety tests
    ///////////////////////////////////////////////

    // risk:ref, par, and liqr all = 1 after set up
    function test_create_unsafe() public {
        // art should not exceed ink, because price par liqr all == 1
        vm.expectRevert(Bank.ErrNotSafe.selector);
        bank.frob(address(this), int(stack), int(stack) + 1);
    }

    function test_safe_return_vals() public {
        file('fee', bytes32(FEE_2X_ANN));
        bank.frob(address(this), int(stack), int(stack));
        (uint deal, uint tot) = bank.safe(self);

        // position should be (barely) safe
        assertTrue(deal == RAY);

        // when safe deal should be 1
        assertEq(deal, RAY);

        // tot should be ink as a rad
        uint tot1 = stack * RAY;
        assertEq(tot, tot1);

        // accumulate fees to 2x...position should sink underwater
        skip(BANKYEAR);
        bank.drip();
        (deal, tot) = bank.safe(self);
        assertTrue(deal < RAY);

        // tab doubled, so deal halved
        assertClose(deal, RAY / 2, 10000000);
        // tot unchanged since it's just ink rad
        assertClose(tot, tot1, 10000000);

        // always safe if debt is zero
        rico_mint(1000 * WAD, true);
        bank.frob(address(this), int(0), - int(_art(self)));
        (deal, tot) = bank.safe(self);
        assertTrue(deal == RAY);
    }

    function test_rack_puts_urn_underwater() public {
        // frob till barely safe
        bank.frob(address(this), int(stack), int(stack));
        (uint deal,) = bank.safe(self);
        assertTrue(deal == RAY);

        // accrue some interest to sink
        skip(100);
        bank.drip();
        (deal,) = bank.safe(self);
        assertTrue(deal < RAY);

        // fee must be >=1
        Bank.BankParams memory p = basic_params;
        p.fee = RAY - 1;
        vm.expectRevert(Bank.ErrBound.selector);
        new Bank(p);
    }

    function test_liqr_puts_urn_underwater() public {
        // frob till barely safe
        bank.frob(address(this), int(stack), int(stack));
        (uint deal,) = bank.safe(self);
        assertTrue(deal == RAY);

        // raise liqr a little bit...should sink the urn
        file('liqr', bytes32(RAY + 1000000));
        (deal,) = bank.safe(self);
        assertTrue(deal < RAY);

        // can't have liqr < 1
        Bank.BankParams memory p = basic_params;
        p.liqr = RAY - 1;
        vm.expectRevert(Bank.ErrBound.selector);
        new Bank(p);

        // lower liqr back down...should refloat the urn
        file('liqr', bytes32(RAY));
        (deal,) = bank.safe(self);
        assertTrue(deal == RAY);
    }

    function test_frob_refloat() public {
        // frob till barely safe
        bank.frob(address(this), int(stack), int(stack));
        (uint deal,) = bank.safe(self);
        assertTrue(deal == RAY);

        // sink the urn
        skip(BANKYEAR);
        bank.drip();
        (deal,) = bank.safe(self);
        assertTrue(deal < RAY);

        // add ink to refloat
        bank.frob(address(this), int(stack), int(0));
        (deal,) = bank.safe(self);
        assertTrue(deal == RAY);
    }

    function test_increasing_risk_sunk_urn() public {
        // frob till barely safe
        bank.frob(address(this), int(stack), int(stack));
        (uint deal,) = bank.safe(self);
        assertTrue(deal == RAY);

        // sink it
        skip(BANKYEAR);
        bank.drip();
        (deal,) = bank.safe(self);
        assertTrue(deal < RAY);

        // should always be able to decrease art or increase ink, even when sunk
        bank.frob(address(this), int(0), int(-1));
        bank.frob(address(this), int(1), int(0));

        // should not be able to decrease ink or increase art of sunk urn
        vm.expectRevert(Bank.ErrNotSafe.selector);
        bank.frob(address(this), int(10), int(1));
        vm.expectRevert(Bank.ErrNotSafe.selector);
        bank.frob(address(this), int(-1), int(-1));
    }

    function test_increasing_risk_safe_urn() public {
        // frob till very safe
        bank.frob(address(this), int(stack), int(10));
        (uint deal,) = bank.safe(self);
        assertTrue(deal == RAY);

        // should always be able to decrease art or increase ink
        bank.frob(address(this), int(0), int(-1));
        bank.frob(address(this), int(1), int(0));

        // should be able to decrease ink or increase art of safe urn
        // as long as resulting urn is safe
        bank.frob(address(this), int(0), int(1));
        bank.frob(address(this), int(-1), int(0));
    }

    function test_basic_bail() public {
        bank.frob(self, int(WAD), int(WAD));
        skip(BANKYEAR);
        bank.bail(self);
    }

    function test_bail_price_1() public {
        // frob to edge of safety
        uint borrow = WAD * 1000;
        file('liqr', bytes32(RAY));
        bank.frob(self, int(borrow), int(borrow));

        // raise urn's debt to 1.5x original...pep is 2, so earn is cubic
        file('fee', bytes32(FEE_1_5X_ANN));
        skip(BANKYEAR);

        // (2/3)**2 for deal**pep, because tab ~= ink * 3 / 2
        uint expected = borrow * 2**2 / 3**2;
        rico_mint(expected, false);
        rico.transfer(address(guy), expected);
        uint earn = guy.bail(self);

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

        file("pep", bytes32(pep));
        file("pop", bytes32(pop));
        file("pup", bytes32(uint(pup)));
        file("fee", bytes32(FEE_1_5X_ANN));

        bank.frob(self, int(1000 * WAD), int(borrow));

        // drop ink/tab to 66%...pep is 1, so earn is linear
        skip(BANKYEAR);
        uint expected = rmul(borrow, rmash(RAY * 2 / 3, pep, pop, pup));
        prepguyrico(expected, false);
        uint earn = guy.bail(self);
        // check returned bytes represent quantity of tokens received
        assertEq(earn, 1000 * WAD);

        // guy was given exact amount, check all was spent for all risk deposit
        assertLt(rico.balanceOf(address(guy)), WAD / 100000);
        assertEq(risk.balanceOf(address(guy)), 1000 * WAD);

        // clamping
        pep = 2; pop = 3 * RAY / 2; pup = -int(RAY / 8);
        file("pep", bytes32(pep));
        file("pop", bytes32(pop));
        file("pup", bytes32(uint(pup)));

        // 2 * borrow because skipped bankyear
        risk_mint(self, 10000 * WAD);
        bank.frob(self, int(2 * borrow), int(borrow));

        // skip a bunch so mash clamps to 0
        skip(BANKYEAR * 10);

        // should give all ink, shouldn't cost any rico
        assertEq(guy.bail(self), 2 * borrow);
        assertLt(rico.balanceOf(address(guy)), WAD / 100000);
    }

    function test_bail_refund() public {
        // set c ratio to double
        uint pop = RAY * 3 / 2;
        uint pep = 2;
        uint borrow = WAD * 500;
        uint dink = borrow * 5 / 2;
        file("liqr", bytes32(RAY * 2));
        file("pep",  bytes32(pep));
        file("pop",  bytes32(pop));
        file("fee",  bytes32(FEE_1_5X_ANN));

        // frob to edge of safety
        bank.frob(self, int(dink), int(borrow));

        // drop to 66%...position is still overcollateralized
        skip(BANKYEAR);

        // deal should be 0.66...still overcollateralized
        rico_mint(borrow, false);
        rico.transfer(address(guy), 3 * borrow * 2 / 3);

        uint deal = RAY * 5 / 2 * 2 / 3 / 2;
        uint mash = rmash(deal, pep, pop, 0);
        uint cost_unclamped = rmul(dink, mash);
        uint tab  = borrow * 3 / 2;
        guy.bail(self);

        // guy should not get all risk, as position was overcollateralized
        // guy gets ink * (borrowed / total ink value)
        uint guy_earn = rmul(dink, rdiv(tab, cost_unclamped));
        assertClose(risk.balanceOf(address(guy)), guy_earn, 1000000);

        // excess ink should be sent back to urn holder, not left in urn
        uint ink_left = _ink(self);
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
        bank.frob(self, int(self_risk_bal0 + 1), 0);

        // revert for trying to exit too much rico
        vm.expectRevert(Bank.ErrNotSafe.selector);
        bank.frob(self, int(10), int(11));

        // revert for trying to exit gems from other users
        vm.expectRevert(Math.ErrUintUnder.selector);
        bank.frob(self, int(-1), 0);

        // gems are taken from user when joining, and rico given to user
        bank.frob(self, int(stack), int(stack / 2));
        uint self_risk_bal1 = risk.balanceOf(self);
        uint self_rico_bal1 = rico.balanceOf(self);
        assertEq(self_risk_bal1 + stack, self_risk_bal0);
        assertEq(self_rico_bal1, self_rico_bal0 + stack / 2);

        // close, even without drip need 1 extra rico as rounding is in systems favour
        rico_mint(1, false);
        bank.frob(self, -int(stack), -int(stack / 2));
        uint self_risk_bal2 = risk.balanceOf(self);
        uint self_rico_bal2 = rico.balanceOf(self);
        assertEq(self_risk_bal0, self_risk_bal2);
        assertEq(self_rico_bal0, self_rico_bal2);
    }

    function test_rejects_unsafe_frob() public {
        uint ink = _ink(self);
        uint art = _art(self);
        assertEq(ink, 0);
        assertEq(art, 0);

        // no collateral...shouldn't be able to borrow
        vm.expectRevert(Bank.ErrNotSafe.selector);
        bank.frob(self, int(0), int(WAD));
    }

    // amount of rico owed to pay down the CDP
    function owed() internal returns (uint) {
        // update rack first
        bank.drip();

        uint rack = bank.rack();
        uint art = _art(self);
        return rack * art;
    }

    function test_drip() public {
        // set a high fee
        file('fee', bytes32(bank.FEE_MAX()));

        // drip a little bit so this isn't the first fee accumulation
        skip(1);
        bank.drip();
        bank.frob(self, int(100 * WAD), int(50 * WAD));

        // wait a second, just so it's more realistic
        skip(1);
        uint debt0 = owed();

        skip(1);
        uint debt1 = owed();
        assertClose(debt1, rmul(debt0, bank.FEE_MAX()), 1_000_000_000_000);
    }

    function test_rest_monotonic() public {
        // set a tiny fee - will accumulate to rest
        file('fee', bytes32(RAY + 2));
        file('dust', bytes32(0));

        // frob a tiny bit more than a wad so lower bits of fee go to rest
        bank.frob(self, int(WAD + 1), int(WAD + 1));

        // drip to accumulate to rest
        skip(1);
        bank.drip();
        assertEq(bank.rest(), 2 * WAD + 2);

        // drip again, should have more rest now
        skip(1);
        bank.drip();
        assertGt(bank.rest(), 2 * WAD + 2);
    }

    function test_rest_drip_0() public {
        // set a tiny fee and frob
        file('fee', bytes32(RAY + 1));
        bank.frob(self, int(WAD), int(WAD));

        // didn't frob any fractional rico, so rest should be (fee - RAY) * WAD
        skip(1);
        bank.drip();
        assertEq(bank.rest(), WAD);

        // do it again, should double
        skip(1);
        bank.drip();
        assertEq(bank.rest(), 2 * WAD);

        // no more fee - rest should stop increasing
        file('fee', bytes32(RAY));
        skip(1);
        bank.drip();
        assertEq(bank.rest(), 2 * WAD);
    }

    function test_rest_drip_toggle_ones() public {
        // drip with no fees
        file('fee', bytes32(RAY));
        file('dust', bytes32(0));
        bank.drip();

        // mint 1 to deal with rounding
        // then lock 1 and wipe 1
        rico_mint(1, true);
        bank.frob(self, int(1), int(1));
        bank.frob(self, -int(1), -int(1));

        // rest from rounding should be RAD / WAD == RAY
        bank.drip();
        assertEq(bank.rest(), RAY);

        // dripping should clear rest
        skip(1);
        bank.drip();
        assertEq(bank.rest(), 0);
    }

    function test_rest_drip_toggle_wads() public {
        // drip with no fees
        file('fee', bytes32(RAY));
        bank.drip();

        // tiny fee, no dust
        file('fee', bytes32(RAY + 1));
        file('dust', bytes32(0));

        // mint 1 for rounding, then frob and drip
        rico_mint(1, true);
        bank.frob(self, int(WAD), int(WAD));
        skip(1);
        bank.drip();

        // rest should be (fee - RAY) * WAD
        assertEq(bank.rest(), WAD);

        // wipe the urn...rest should be WAD + (WAD * (RAY + 1)) / RAY + 1
        // or iow the debt change minus the debt change rounded down by 1
        uint art = _art(self);
        bank.frob(self, int(0), -int(art));
        assertEq(bank.rest(), RAY);

        // rest is RAY (rest % RAY == 0), so should accumulate to joy
        skip(1);
        bank.drip();
        assertEq(bank.rest(), 0);
    }

    function test_drip_neg_fee() public {
        // can't set fee < RAY
        Bank.BankParams memory p = basic_params;
        p.fee = RAY / 2;
        vm.expectRevert(Bank.ErrBound.selector);
        new Bank(p);

        file('fee', bytes32(RAY));

        // fees should be based on previous rate rather than new
        skip(10);
        uint pre_joy = bank.joy();
        file('fee', bytes32(bank.FEE_MAX()));
        uint aft_joy = bank.joy();
        uint rake = aft_joy - pre_joy;
        // previous rate was RAY (zero fees)
        assertEq(rake, 0);
    }

    function test_par() public {
        assertEq(bank.par(), RAY);
        bank.frob(self, int(100 * WAD), int(50 * WAD));
        (uint deal,) = bank.safe(self);
        assertEq(deal, RAY);

        // par increase should increase collateral requirement
        // -> urn sinks
        file('par', bytes32(RAY * 3));
        (deal,) = bank.safe(self);
        assertLt(deal, RAY);
    }

    function test_frob_err_ordering_1() public {
        // high fee, medium dust
        file('fee', bytes32(FEE_2X_ANN));
        file('dust', bytes32(RAY / 100));

        // accumulate pending fees
        skip(BANKYEAR);
        bank.drip();

        // ceily, not safe, wrong urn, dusty...should be wrong urn
        vm.expectRevert(Bank.ErrWrongUrn.selector);
        bank.frob(abank, int(WAD / 2), int(WAD / 2));

        // right urn, should be unsafe
        vm.expectRevert(Bank.ErrNotSafe.selector);
        bank.frob(self, int(WAD / 2), int(WAD / 2 - 1));

        // safe, should be dusty
        vm.expectRevert(Bank.ErrUrnDust.selector);
        bank.frob(self, int(2 * WAD), int(WAD / 2 - 1));

        //non-dusty, should be good
        bank.frob(self, int(200 * WAD), int((WAD + WAD / 1_000) / 2 ));
    }

    function test_frob_err_ordering_darts() public {
        // medium dust
        file('dust', bytes32(RAY / 100));

        // check how it works with some fees dripped
        file('fee', bytes32(bank.FEE_MAX()));
        skip(1);
        bank.drip();

        // frob while pranking fakesrc address
        risk_mint(fakesrc, 1000 * WAD);
        vm.startPrank(fakesrc);
        int dart = int(1 + WAD * RAY / bank.FEE_MAX());
        bank.frob(fakesrc, int(200 * WAD), dart);

        vm.stopPrank();

        // bypasses most checks when dart <= 0
        // can't hurt because permissions
        vm.expectRevert(Bank.ErrWrongUrn.selector);
        bank.frob(fakesrc, -int(199 * WAD), int(0));
        vm.expectRevert(Bank.ErrWrongUrn.selector);
        bank.frob(fakesrc, int(0), int(1));

        // ok now fakesrc frobs its own urn...but it's not safe
        vm.startPrank(fakesrc);
        vm.expectRevert(Bank.ErrNotSafe.selector);
        bank.frob(fakesrc, -int(199 * WAD), 0);

        // still can't free because dust
        vm.expectRevert(Bank.ErrUrnDust.selector);
        bank.frob(fakesrc, -int(199 * WAD), -dart + 100);
        vm.stopPrank();

        // make it safe...should be dusty
        vm.expectRevert(Bank.ErrUrnDust.selector);
        bank.frob(self, int(WAD), int(1));

        // not dusty, should be ok
        bank.frob(self, int(500 * WAD), int(WAD));
    }

    function test_frob_err_ordering_dinks_1() public {
        // high fee, medium dust
        file('fee', bytes32(FEE_2X_ANN));
        file('dust', bytes32(RAY / 100));

        // accumulate pending fees
        skip(1);
        bank.drip();

        risk_mint(fakesrc, 1000 * WAD);

        // frob from fakesrc address
        // could prank any non-self address, just chose fakesrc's
        vm.startPrank(fakesrc);
        bank.frob(fakesrc, int(500 * WAD), int(1 + WAD * RAY / FEE_2X_ANN));
        vm.stopPrank();

        // self removes some ink from fakesrc - should fail because unauthorized
        vm.expectRevert(Bank.ErrWrongUrn.selector);
        bank.frob(fakesrc, -int(WAD), int(0));

        // fakesrc removes some ink from fakesrc - should fail because not safe
        vm.prank(fakesrc);
        vm.expectRevert(Bank.ErrNotSafe.selector);
        bank.frob(fakesrc, -int(500 * WAD), int(0));

        // ...but it's fine when dink >= 0
        bank.frob(fakesrc, int(0), int(0));
        bank.frob(fakesrc, int(1), int(0));
    }

    function test_frob_err_ordering_dinks_darts() public {
        // high fee, medium dust
        file('fee', bytes32(FEE_2X_ANN));
        file('dust', bytes32(RAY / 100));

        // accumulate pending fees
        skip(1);
        bank.drip();

        risk_mint(fakesrc, 1000 * WAD);

        // could prank anything non-self; chose fakesrc
        vm.startPrank(fakesrc);
        int dart = int(1 + WAD * RAY / FEE_2X_ANN);
        bank.frob(fakesrc, int(500 * WAD), dart);

        // 2 for accumulated debt, 1 for rounding
        rico.transfer(self, 3);
        vm.stopPrank();

        // can't steal ink or art from someone else's urn
        vm.expectRevert(Bank.ErrWrongUrn.selector);
        bank.frob(fakesrc, -int(WAD), int(0));
        vm.expectRevert(Bank.ErrWrongUrn.selector);
        bank.frob(fakesrc, int(0), int(1));

        // ...can remove ink from your own, but it has to be safe
        vm.prank(fakesrc);
        vm.expectRevert(Bank.ErrNotSafe.selector);
        bank.frob(fakesrc, -int(499 * WAD), int(1));

        // nothing wrong with frobbing 0
        bank.frob(fakesrc, int(0), int(0));

        // can't reduce ink below dust
        vm.prank(fakesrc);
        vm.expectRevert(Bank.ErrUrnDust.selector);
        bank.frob(fakesrc, -int(499 * WAD), -dart + 100);

        // ...lower dust - now it's fine
        file('dust', bytes32(RAY / 1000000000000000));

        vm.prank(fakesrc);
        bank.frob(fakesrc, -int(499 * WAD), -dart + 100);
        vm.stopPrank();
    }

    function test_dtab_not_normalized() public {
        // accumulate pending fees, then set fee high
        bank.drip();
        file('fee', bytes32(FEE_2X_ANN));

        // rack is 0, so debt should increase by dart
        bank.frob(self, int(100 * WAD), int(WAD));
        assertEq(bank.tart(), WAD);

        skip(BANKYEAR);
        bank.drip();

        // dart > 0, so dtab > 0
        // dart == 1, rack == 2, so dtab should be 2
        uint ricobefore = rico.balanceOf(self);
        bank.frob(self, int(WAD), int(WAD));
        uint ricoafter  = rico.balanceOf(self);
        assertClose(ricoafter, ricobefore + WAD * 2, 1_000_000);

        // dart < 0 -> dtab < 0
        // dart == -1, rack == 2 -> dtab should be -2
        // minus some change for rounding
        ricobefore = rico.balanceOf(self);
        bank.frob(self, int(0), -int(WAD));
        ricoafter = rico.balanceOf(self);
        assertClose(ricoafter, ricobefore - (WAD * 2 + 1), 1_000_000);
    }

    function test_drip_all_rest_1() public {
        file('fee', bytes32(FEE_1_5X_ANN));

        // raise rack to 1.5
        skip(BANKYEAR);
        // now frob 1, so debt is 1
        // and rest is 0.5 * RAY
        bank.drip();
        bank.frob(self, int(1000), int(1));
        assertClose(bank.rest(), RAY / 2, 1_000_000);
        assertEq(bank.tart(), 1);
        // need to wait for drip to do anything...
        bank.drip();
        assertClose(bank.rest(), RAY / 2, 1_000_000);

        // frob again so rest reaches RAY
        bank.frob(self, int(1), int(1));
        assertEq(bank.tart(), 2);
        assertClose(bank.rest(), RAY, 1_000_000);

        // so regardless of fee next drip should drip 1 (== rest / RAY)
        file('fee', bytes32(RAY));
        skip(1);
        bank.drip();

        assertEq(bank.tart(), 2);
        assertLt(bank.rest(), RAY / 1_000_000);
        assertEq(rico.totalSupply(), 2);
        assertEq(bank.joy(), 1);
        assertEq(bank.joy() + rico.totalSupply(), rmul(bank.tart(), bank.rack()));
    }

    function test_bail_drips() public {
        bank.frob(self, int(WAD), int(WAD));

        // accrue fees for a year
        skip(BANKYEAR);

        // bail should accumulate pending fees before liquidating
        // -> bail should update rack
        uint prevrack = bank.rack();
        bank.bail(self);
        assertGt(bank.rack(), prevrack);
    }

    // make sure bailed ink decodes properly
    function test_bail_return_value() public {
        file('fee', bytes32(FEE_2X_ANN));
        bank.frob(self, int(WAD), int(WAD));

        // skip a lot so no refund
        skip(BANKYEAR * 10);
        uint sold = bank.bail(self);
        assertEq(sold, WAD);
    }

    function test_ink_return_value() public {
        bank.frob(self, int(WAD), int(WAD));
        uint ink = _ink(self);
        assertEq(ink, WAD);
    }

    function test_bail_pop_pep_1() public {
        // set pep and pop to something awk
        uint pep = 3;
        uint pop = 5 * RAY;
        file('pep', bytes32(pep));
        file('pop', bytes32(pop));
        file('fee', bytes32(FEE_2X_ANN));

        bank.frob(self, int(WAD), int(WAD));

        // make it very unsafe
        skip(3 * BANKYEAR);

        // bail should charge proportional to pop * underwater-ness ^ pop
        uint pre_rico = rico.balanceOf(self);
        bank.bail(self);
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
        file('pep', bytes32(pep));
        file('pop', bytes32(pop));
        file('fee', bytes32(FEE_2X_ANN));

        bank.frob(self, int(WAD), int(WAD));

        // set high liqr, low price
        file('liqr', bytes32(liqr));

        skip(4 * BANKYEAR);

        // liqr, price, pep and pop should all affect bail revenue
        uint pre_rico = rico.balanceOf(self);
        bank.bail(self);
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
        bank.frob(self, int(WAD), int(WAD));

        file('pep', bytes32(uint(4)));

        // a lot of (feasible) accumulated fees
        file('fee', bytes32(FEE_2X_ANN));
        skip(BANKYEAR * 5);

        // shouldn't cause an overflow in deal/earn calc
        bank.bail(self);
    }

    function test_frob_safer_over_ceilings() public {
        // should be able to pay down urns that are over ceiling
        bank.frob(self, int(2000 * WAD), int(1000 * WAD));

        // over line
        file('line', bytes32(0));

        // safer dart
        bank.frob(self, int(0), -int(WAD));

        // safer dink (hook property - vat doesn't care)
        bank.frob(self, int(WAD), 0);

        // safer dart and dink
        bank.frob(self, int(WAD), -int(WAD));

        // under line
        file('line', bytes32(UINT256_MAX));
        bank.frob(self, int(0), -int(WAD));
        bank.frob(self, int(WAD), 0);

        // under line
        file('line', bytes32(UINT256_MAX));
        bank.frob(self, int(0), -int(WAD));
        bank.frob(self, int(WAD), 0);
    }

    function test_wipe_not_safer_over_ceilings() public {
        bank.frob(self, int(2000 * WAD), int(1000 * WAD));

        file('line', bytes32(0));

        // shouldn't do ceiling check on wipe,
        // even if frob makes CDP less safe
        bank.frob(self, -int(WAD), -int(WAD));
    }

    function test_bail_moves_line() public {
        // defensive line
        uint dink   = WAD * 500;
        uint borrow = WAD * 500;
        uint line0  = RAD * 1000;

        // set some semi-normal values for line liqr pep pop
        // doesn't matter too much, this test just cares about change in sin
        file('line', bytes32(line0));
        file("liqr", bytes32(RAY));
        file("pep",  bytes32(uint(1)));
        file("pop",  bytes32(RAY));
        file("fee",  bytes32(FEE_2X_ANN));


        // frob to edge of safety and line (pending year wait)
        bank.frob(self, int(dink), int(borrow));

        // double tab
        skip(BANKYEAR);

        uint sr0   = rico.balanceOf(self);
        uint sg0   = risk.balanceOf(self);
        bank.bail(self);
        uint line1 = bank.line();
        uint sr1   = rico.balanceOf(self);
        uint sg1   = risk.balanceOf(self);

        // rico recovery will be borrowed amount * 0.5 for ink/tab * 0.5 for deal
        // line should have decreased to 50% capacity
        assertClose(line0 / 4, line1, 10000);
        assertClose(sr0, sr1 + borrow * 2 / 4, 10000);
        assertEq(sg0, sg1 - dink);

        // line got defensive, so should be barely too low now
        vm.expectRevert(Bank.ErrDebtCeil.selector);
        bank.frob(self, int(dink), int(borrow / 4 * 100001 / 100000));
        // barely under line
        bank.frob(self, int(dink), int(borrow / 4));

        // set really low line to test defensive line underflow
        file('line', bytes32(line0 / 10));

        // another big fee accumulation, then bail
        skip(2 * BANKYEAR);
        bank.bail(self);

        // fees or line modifications can lead to loss > capacity, check no underflow
        uint line2 = bank.line();
        assertEq(line2, 0);
    }

    function test_risk_denominated_dust() public {
        uint sup = risk.totalSupply();
        uint dust = RAY * 5 / sup;
        file('dust', bytes32(dust));

        // art is 0 so it's fine
        bank.frob(self, int(1), 0);
        bank.frob(self, -int(1), 0);

        // art is nonzero so it's not fine
        vm.expectRevert(Bank.ErrUrnDust.selector);
        bank.frob(self, int(3), int(1));

        file('dust', bytes32(dust / 2));
        bank.frob(self, int(3), int(1));
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
