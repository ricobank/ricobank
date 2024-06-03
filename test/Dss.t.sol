// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.25;

import "forge-std/Test.sol";

import {
    RicoSetUp, Guy, Vat, Vow, Gem, Ball, File, Bank
} from "./RicoHelper.sol";

contract Usr is Guy {
    constructor(address payable _bank) Guy(_bank) {}

    receive () external payable {}

    function try_call(address addr, bytes calldata data) external returns (bool) {
        bytes memory _data = data;
        assembly {
            let ok := call(gas(), addr, 0, add(_data, 0x20), mload(_data), 0, 0)
            let free := mload(0x40)
            mstore(free, ok)
            mstore(0x40, add(free, 32))
            revert(free, 32)
        }
    }

    function can_frob(bytes32 ilk, address u, int dink, int dart)
      public returns (bool) {
        string memory sig = "frob(bytes32,address,int256,int256)";
        bytes memory data = abi.encodeWithSignature(sig, ilk, u, dink, dart);

        string memory callsig  = "try_call(address,bytes)";
        bytes  memory can_call = abi.encodeWithSignature(callsig, bank, data);
        (,bytes memory res) = address(this).call(can_call);

        return abi.decode(res, (bool));
    }
}

contract DssJsTest is Test, RicoSetUp {
    uint init_join = 1000;
    uint stack     = WAD * 10;

    Usr ali;
    Usr bob;
    Usr cat;

    address a;
    address b;
    address c;

    uint riskprice    = 40 * RAY / 110;
    uint starting_gem = 10000 * WAD;

    function setUp() public {
        make_bank();
        init_risk();

        // no fee, lower line a bit, burn the risk
        Vat(bank).filk(rilk, bytes32('fee'), bytes32(uint(RAY)));
        Vat(bank).filk(rilk, 'line', bytes32(1000 * RAD));
        risk.burn(self, risk.balanceOf(self));

        // mint some RISK so rates relative to total supply aren't zero
        risk.mint(address(1), 2620000 * WAD);

        ali = new Usr(bank);
        bob = new Usr(bank);
        cat = new Usr(bank);
        guy = new Guy(bank);
        ali.approve(address(risk), bank, UINT256_MAX);
        bob.approve(address(risk), bank, UINT256_MAX);
        cat.approve(address(risk), bank, UINT256_MAX);
        a = address(ali);
        b = address(bob);
        c = address(cat);

        // mint ramp has been charging for 1s
        File(bank).file('bel', bytes32(block.timestamp - 1));
    }

}

contract DssVatTest is DssJsTest {
    function _vat_setUp() internal {}
    modifier _vat_ { _vat_setUp(); _; }
}

contract DssFrobTest is DssVatTest {

    function _frob_setUp() internal _vat_ {
        risk.mint(self, 1000 * WAD);
    }

    modifier _frob_ { _frob_setUp(); _; }

    function test_setup() public _frob_ {
        assertEq(risk.balanceOf(self), 1000 * WAD);
    }

    function test_lock() public _frob_ {
        // no urn created yet
        assertEq(_ink(rilk, self), 0);

        // lock some ink without borrowing
        Vat(bank).frob(rilk, self, int(6 * WAD), 0);
        assertEq(_ink(rilk, self), 6 * WAD);
        assertEq(risk.balanceOf(self), 994 * WAD);

        // remove the ink
        Vat(bank).frob(rilk, self, -int(6 * WAD), 0);
        assertEq(_ink(rilk, self), 0);
        assertEq(risk.balanceOf(self), 1000 * WAD);
    }

    function test_calm() public _frob_ {
        // calm means that the debt ceiling is not exceeded
        // it's ok to increase debt as long as you remain calm
        Vat(bank).filk(rilk, 'line', bytes32(10 * RAD));
        Vat(bank).frob(rilk, self, int(10 * WAD), int(9 * WAD));

        // only if under debt ceiling
        vm.expectRevert(Vat.ErrDebtCeil.selector);
        Vat(bank).frob(rilk, self, int(WAD), int(2 * WAD));

        // but safe check comes first
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(rilk, self, int(0), int(2 * WAD));

        // calm line
        Vat(bank).filk(rilk, 'line', bytes32(20 * RAD));

        // but not ceil
        File(bank).file('ceil', bytes32(10 * WAD));
        vm.expectRevert(Vat.ErrDebtCeil.selector);
        Vat(bank).frob(rilk, self, int(2 * WAD), int(2 * WAD));

        // ok calm down
        File(bank).file('ceil', bytes32(20 * WAD));
        Vat(bank).frob(rilk, self, int(2 * WAD), int(2 * WAD));
    }

    function test_cool() public _frob_ {
        // cool means that the debt has decreased
        // it's ok to be over the debt ceiling as long as you're cool
        Vat(bank).filk(rilk, 'line', bytes32(10 * RAD));
        Vat(bank).frob(rilk, self, int(10 * WAD), int(8 * WAD));
        Vat(bank).filk(rilk, 'line', bytes32(5 * RAD));

        // can decrease debt when over ceiling
        Vat(bank).frob(rilk, self, int(0), -int(WAD));
    }

    function test_safe() public _frob_ {
        // safe means that the cdp is not risky
        // you can't frob a cdp into unsafe
        Vat(bank).frob(rilk, self, int(10 * WAD), int(5 * WAD));
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(rilk, self, int(0), int(6 * WAD));
    }

    function test_nice() public _frob_ {
        // nice means that the collateral has increased or the debt has
        // decreased. remaining unsafe is ok as long as you're nice
        Vat(bank).frob(rilk, self, int(10 * WAD), int(10 * WAD));

        Vat(bank).filk(rilk, 'fee', bytes32(FEE_2X_ANN));
        skip(BANKYEAR);

        // debt can't increase if unsafe
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(rilk, self, int(0), int(WAD));

        // debt can decrease
        Vat(bank).frob(rilk, self, int(0), -int(WAD));

        // ink can't decrease
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(rilk, self, -int(WAD), 0);

        // ink can increase
        Vat(bank).frob(rilk, self, int(WAD), 0);

        // cdp is still unsafe
        // ink can't decrease, even if debt decreases more
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(rilk, self, -int(2 * WAD), -int(4 * WAD));

        // debt can't increase, even if ink increases more
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(rilk, self, int(5 * WAD), int(WAD));

        // ink can decrease if end state is safe
        Vat(bank).frob(rilk, self, -int(WAD), -int(4 * WAD));

        // debt can increase if end state is safe
        Vat(bank).frob(rilk, self, int(5 * WAD), int(WAD));
    }

    function test_alt_callers() public _frob_ {
        risk.mint(a, 20 * WAD);
        risk.mint(b, 20 * WAD);
        risk.mint(c, 20 * WAD);

        // ali opens an urn to see what bob and cat can do with it
        ali.frob(rilk, a, int(10 * WAD), int(5 * WAD));

        // anyone can lock
        assertTrue(ali.can_frob(rilk, a, int(WAD), 0));
        assertTrue(bob.can_frob(rilk, b, int(WAD), 0));
        assertTrue(cat.can_frob(rilk, c, int(WAD), 0));

        // but only with own gems - ***N/A no v or w***

        // only the lad can free
        assertTrue(ali.can_frob(rilk, a, -int(WAD), 0));
        vm.expectRevert(Vat.ErrWrongUrn.selector);
        bob.frob(rilk, a, -int(WAD), 0);
        vm.expectRevert(Vat.ErrWrongUrn.selector);
        cat.frob(rilk, a, -int(WAD), 0);

        // the lad can free to anywhere - ***N/A no v or w***

        // only the lad can draw
        assertTrue(ali.can_frob(rilk, a, int(0), int(WAD)));
        vm.expectRevert(Vat.ErrWrongUrn.selector);
        bob.frob(rilk, a, int(0), int(WAD));
        vm.expectRevert(Vat.ErrWrongUrn.selector);
        cat.frob(rilk, a, int(0), int(WAD));

        // lad can draw to anywhere - ***N/A no v or w***

        rico.mint(b, WAD + 1); // +1 for rounding in system's favour
        rico.mint(c, WAD + 1);

        // anyone can wipe
        assertTrue(ali.can_frob(rilk, a, int(0), -int(WAD)));
        assertTrue(bob.can_frob(rilk, a, int(0), -int(WAD)));
        assertTrue(cat.can_frob(rilk, a, int(0), -int(WAD)));

        // but only with their own dai - ***N/A no v or w***
    }

    function test_hope() public _frob_ {
        risk.mint(a, 20 * WAD);
        risk.mint(b, 20 * WAD);
        risk.mint(c, 20 * WAD);

        // ali opens an urn to test what bob and cat can do with it
        ali.frob(rilk, a, int(10 * WAD), int(5 * WAD));

        // only owner (ali) can do risky actions
        assertTrue(ali.can_frob(rilk, a, int(0), int(WAD)));
        vm.expectRevert(Vat.ErrWrongUrn.selector);
        bob.frob(rilk, a, int(0), int(WAD));
        vm.expectRevert(Vat.ErrWrongUrn.selector);
        cat.frob(rilk, a, int(0), int(WAD));

        // unless they hope another user - ***N/A no hope***
    }

    function test_dust() public _frob_ {
        rico_mint(1, true); // +1 for rounding in system's favour

        // frob a normal amount, but then set dust above urn's debt
        Vat(bank).frob(rilk, self, int(9 * WAD), int(WAD));
        Vat(bank).filk(rilk, 'dust', bytes32(5 * RAD));

        // draw to dusty amount
        vm.expectRevert(Vat.ErrUrnDust.selector);
        Vat(bank).frob(rilk, self, int(5 * WAD), int(2 * WAD));
        Vat(bank).frob(rilk, self, int(0), int(5 * WAD));

        // wipe to dusty amount
        vm.expectRevert(Vat.ErrUrnDust.selector);
        Vat(bank).frob(rilk, self, int(0), -int(5 * WAD));
        Vat(bank).frob(rilk, self, int(0), -int(6 * WAD));
    }
}

contract DssBiteTest is DssVatTest {

    function _bite_setUp() internal
    {
        _vat_setUp();
        risk.mint(self, 100 * WAD);

        // jug N/A
        //   rico has fee, no jug
        //   dss setup doesn't actually set the fee, just creates the jug

        risk.mint(self, 1000 * WAD);

        // normal line, no liquidation penalty
        Vat(bank).filk(rilk, 'line', bytes32(1000 * RAD));
        Vat(bank).filk(rilk, 'chop', bytes32(RAY));

        // cat.box - ***N/A bail liquidates entire urn***

        risk.approve(bank, UINT256_MAX);

        // risk approve flap - ***N/A vow uses mint and burn***
    }

    modifier _bite_ { _bite_setUp(); _; }

    // test_set_dunk_multiple_ilks
    //   N/A no dunk equivalent, auctions off whole thing at once

    // test_cat_set_box
    //   N/A bail liquidates entire urn, no box

    // test_bite_under_dunk
    //   N/A no dunk analogue, vat can only bail entire urn

    // test_bite_over_dunk
    //   N/A no dunk analogue, vat can only bail entire urn


    function vow_Awe() internal view returns (uint) { return Vat(bank).sin(); }

    // vow_Woe N/A - no debt queue in vow

    function _surp() public view returns (int) {
        int joy = int(Vat(bank).joy());
        int sin = int(Vat(bank).sin() / RAY);
        return joy - sin;
    }

    function test_happy_bite() public _bite_ {
        // create urn (push, frob)
        File(bank).file('par', bytes32(RAY * 4 / 10));
        Vat(bank).frob(rilk, self, int(40 * WAD), int(100 * WAD));
        risk.mint(self, 10000 * WAD);
        risk.burn(self, risk.balanceOf(self) - 960 * WAD);

        // make urn unsafe, set liquidation penalty
        Vat(bank).filk(rilk, 'liqr', bytes32(RAY * 2));
        Vat(bank).filk(rilk, 'pop',  bytes32(RAY * 2));
        Vat(bank).filk(rilk, 'chop', bytes32(RAY * 11 / 10));

        assertEq(_ink(rilk, self), 40 * WAD);
        assertEq(_art(rilk, self), 100 * WAD);
        // Woe - ***N/A - no debt queue (Sin) in vow***
        assertEq(risk.balanceOf(self), 960 * WAD);

        // => bite everything
        // dss checks joy 0 before tend, rico checks before bail
        assertEq(Vat(bank).joy(), 0);

        // cat.file dunk - ***N/A vat always bails whole urn***
        // cat.litter - ***N/A vat always bails urn immediately***
        prepguyrico(200 * WAD, true);
        guy.bail(rilk, self);

        // guy takes all the ink
        assertEq(_ink(rilk, self), 0);
        assertEq(risk.balanceOf(address(guy)), 40 * WAD);

        // difference from dss: no flops; keep just does nothing on deficit
        skip(1);
        prepguyrico(550 * WAD, true);
        int surp_0 = _surp();
        guy.keep(single(rilk));
        assertEq(_surp(), surp_0);
    }

    // test_partial_litterbox
    //   N/A bail liquidates whole urn, dart == art

    // testFail_fill_litterbox
    //   N/A bail liquidates whole urn

    // testFail_dusty_litterbox
    //   N/A bail liquidates whole urn, and there's no liquidation limit
    //   besides debt ceiling

    // test_partial_litterbox_multiple_bites
    //   N/A bail liquidates whole urn in one tx, no liquidation limit (litterbox)

    // testFail_null_auctions_dart_realistic_values
    //   N/A vow has no dustiness check, just liquidates entire urn

    // testFail_null_auctions_dart_artificial_values
    //   N/A no box, bail liquidates entire urn immediately

    // testFail_null_auctions_dink_artificial_values

    // testFail_null_auctions_dink_artificial_values_2
    //   N/A no dunk, vow always bails whole urn

    // testFail_null_spot_value
    //   N/A bail amount doesn't depend on spot, only reverts if urn is safe

    function testFail_vault_is_safe() public _bite_ {
        Vat(bank).frob(rilk, self, int(100 * WAD), int(150 * WAD));

        assertEq(_ink(rilk, self), 100 * WAD);
        assertEq(_art(rilk, self), 150 * WAD);
        // Woe N/A - no debt queue (Sin) in vow
        assertEq(risk.balanceOf(self), 900 * WAD);

        // dunk, litter N/A bail liquidates whole urn in one tx, no litterbox
        vm.expectRevert('ERR_SAFE');
        Vat(bank).bail(rilk, self);
    }

    function test_floppy_bite() public _bite_ {
        Vat(bank).filk(rilk, 'fee', bytes32(FEE_2X_ANN));
        File(bank).file('par', bytes32(RAY * 4 / 10));
        uint ricoamt = 100 * WAD;

        Vat(bank).frob(rilk, self, int(40 * WAD), int(ricoamt));

        skip(BANKYEAR);

        // dunk N/A bail always liquidates whole urn
        // vow.sin N/A no debt queue
        assertEq(Vat(bank).sin() / RAY, 0);
        assertEq(Vat(bank).joy(), 0);
        Vat(bank).bail(rilk, self);
        assertClose(Vat(bank).sin() / RAY, ricoamt * 2, 10000000);

        // bailed, but also dripped ricoamt joy when skipping bankyear
        uint pep  = uint(Vat(bank).get(rilk, 'pep'));
        uint pop  = uint(Vat(bank).get(rilk, 'pop'));
        uint mash = rmash(RAY / 2, pep, pop, 0);
        uint earn = rmul(WAD * 40, mash);
        assertClose(Vat(bank).joy() - ricoamt, earn, 10000000);
        assertClose(Vat(bank).sin() / RAY, 2 * ricoamt, 100000000);
    }

    function test_flappy_bite() public _bite_ {
        uint amt = 100 * WAD;
        force_fees(amt);

        assertEq(vow_Awe() / RAY, 0);

        // risk:rico price 1
        set_dxm('dam', RAY);

        uint prerisk = risk.balanceOf(self);

        // should flap
        Vow(bank).keep(single(rilk));
        assertEq(rico.balanceOf(bank), 0);
        assertEq(vow_Awe() / RAY, 0);

        assertClose(risk.balanceOf(self), prerisk - amt, 1000000000000);

        set_dxm('dam', RAY);

        Vow(bank).keep(single(rilk));

        // no surplus or deficit
        assertEq(rico.balanceOf(bank), 0);
        assertEq(vow_Awe() / RAY, 0);

        // the second keep burnt the RISK bought earlier
        assertEq(risk.balanceOf(bank), 0);
    }
}

contract DssFoldTest is DssVatTest {
    function _fold_setup() internal {
        _vat_setUp();
        File(bank).file('ceil', bytes32(100 * RAD));
        Vat(bank).filk(rilk, 'line', bytes32(100 * RAD));
    }

    modifier _fold_ { _fold_setup(); _; }

    function draw(bytes32 ilk, uint amt) internal {
        risk.mint(self, amt);
        Vat(bank).drip(rilk);
        Vat(bank).frob(ilk, self, int(WAD), int(amt));
    }

    function tab(bytes32 ilk, address _urn) internal view returns (uint) {
        uint art = _art(ilk, _urn);
        uint rack = Vat(bank).ilks(ilk).rack;
        return art * rack;
    }

    function test_fold() public _fold_ {
        uint fee = Vat(bank).ilks(rilk).fee;
        assertEq(fee, RAY);
        draw(rilk, WAD);

        // high fee
        Vat(bank).filk(rilk, 'fee', bytes32(Vat(bank).FEE_MAX()));
        assertEq(tab(rilk, self), RAD);

        // drip should accumulate 1/20 the urn's tab from 1s ago.
        // fee_max is 10X/year: 668226 sec for 5% growth; log(1.05)/log(10)*seconds/year
        skip(668226);
        uint mejoy0 = Vat(bank).joy() * RAY; // rad
        Vat(bank).drip(rilk);
        uint djoy = Vat(bank).joy() * RAY - mejoy0;
        uint tol = RAD / 1000;

        uint actual = RAD * 21 / 20;
        assertGt(tab(rilk, self), actual - tol);
        assertLt(tab(rilk, self), actual + tol);

        actual = RAD / 20;
        assertGt(djoy, actual - tol);
        assertLt(djoy, actual + tol);
    }
}

// testFail_tend_empty
// test_tend
// test_tend_dent_same_bidder
// test_beg
// test_tick
//   N/A rico has no standing auction mechanism

// ClipperTest - N/A no standing auction mechanism
contract DssClipTest is DssJsTest {
    Usr gal;

    function _clip_setup() internal {
        // vault already has a bunch of rico (dai) and gem (risk)...skip transfers
        // rico (dai) already wards port (DaiJoin)
        // rico has no dog, accounts interact with vow directly
        // already have rilk, no need to init ilk
        // no need to join

        riskprice = 5 * RAY;
        risk.mint(self, 1000 * WAD);

        Vat(bank).filk(rilk, 'liqr', bytes32(2 * RAY)); // dss mat
        Vat(bank).filk(rilk, 'dust', bytes32(20 * RAD));
        Vat(bank).filk(rilk, 'line', bytes32(10000 * RAD));

        File(bank).file('ceil', bytes32(10000 * RAD));

        // dss uses wad, rico uses ray
        Vat(bank).filk(rilk, 'chop', bytes32(11 * RAY / 10));

        // hole, Hole N/A (similar to cat.box), no rico equivalent, rico bails entire urn
        // dss clipper N/A, no standing auction mechanism

        // frob some rico, then make the urn unsafe
        // use par to mint so much tab because no other way currently
        // direct par modification doesn't happen in practice
        File(bank).file('par', bytes32(RAY / 10));
        Vat(bank).frob(rilk, self, int(40 * WAD), int(100 * WAD));
        File(bank).file('par', bytes32(RAY));

        // dss me/ali/bob hope clip N/A, rico vat wards vow

        rico_mint(3000 * WAD, false);
        rico.transfer(a, 1000 * WAD);
        rico.transfer(b, 1000 * WAD);
    }

    modifier _clip_ { _clip_setup(); _; }

    // test_change_dog
    //   N/A rico flow has per-auction vow (dss dog)

    // test_get_chop
    //   N/A rico has no dss chop function equivalent, just uses vat.ilks

    // test_kick_4 N/A no standing auction mechanism
        // this test became so laden with changes it doesn't make sense to have

    function test_kick_zero_price() public _clip_ {
        // difference from dss: bail (bark) shouldn't fail on 0 price
        Vat(bank).bail(rilk, self);
    }

    // testFail_redo_zero_price
    //   N/A rico has no auction

    function test_kick_zero_lot() public _clip_ {
        // difference from dss: no standing auction mechanism

        // wipe the urn so it's empty
        Vat(bank).frob(rilk, self, int(0), -int(_art(rilk, self)));

        // can't bail empty urn
        vm.expectRevert(Vat.ErrSafeBail.selector);
        Vat(bank).bail(rilk, self);
    }

    // test_kick_zero_usr
    //   N/A rico has no auction

    // difference from dss: opposite behavior, bail takes the whole urn, refunds later
    function test_bark_not_leaving_dust() public _clip_ {
        Vat(bank).filk(rilk, 'fee', bytes32(FEE_2X_ANN));
        skip(4 * BANKYEAR);
        Vat(bank).bail(rilk, self);

        uint art = _art(rilk, self);
        assertEq(art, 0);
    }

    // test_bark_not_leaving_dust_over_hole
    //   N/A rico has no hole

    // test_bark_not_leaving_dust_rate
    //   N/A dart depends on hole, rico doesn't have hole, always takes entire urn
    //   and refunds later

    // test_bark_only_leaving_dust_over_hole_rate
    // test_Hole_hole
    // test_partial_liquidation_Hole_limit
    // test_partial_liquidation_hole_limit
    //   N/A no hole or Hole or partial liquidations

    // test_take_*, testFail_take_*, test_auction_*
    //   N/A no standing auction, rico v1 goes through uniswapv3

    // test_redo_*
    //   N/A currently no way to reset dead auctions

    // test_stopped_*
    //   N/A no stopped/pause

    // test_incentive_max_values
    //   N/A rico is an MEV snack

    // test_Clipper_yank
    //   N/A no shutdown

    // test_remove_id
    // testFail_id_out_of_range
    //   N/A rico doesn't keep flow auctions as a list because maximum auction id is so high


    // testFail_not_enough_dai
    // testFail_reentrancy_take
    // testFail_reentrancy_redo
    // testFail_reentrancy_kick
    // testFail_reentrancy_file_uint
    // testFail_reentrancy_file_addr
    // testFail_reentrancy_yank
    // testFail_take_impersonation
    // test_gas_partial_take
    // test_gas_full_take
    // test_gas_bark_kick
    //   N/A no standing auction, no take
    //   also no clipper-like callback

}

// end
//   N/A no end
// cure
//   N/A no cure, only thing that uses cure is end
// dai
//   N/A rico uses gem, already tested

contract DssVowTest is DssJsTest {
    function _vow_setUp() internal {
        risk.mint(self, 10000 * WAD);
        risk.approve(bank, UINT256_MAX);
        File(bank).file('bel', bytes32(block.timestamp));
    }
    modifier _vow_ { _vow_setUp(); _; }

    // test_flog_wait
    //   N/A no vow.wait in rico

    // test_no_reflop
    //   N/A no flop

    function test_flap_1() public _vow_ {
        risk.mint(self, 10000 * WAD);
        Vat(bank).drip(rilk);
        Vat(bank).filk(rilk, bytes32('chop'), bytes32(RAY * 11 / 10));
        Vat(bank).filk(rilk, 'fee', bytes32(Vat(bank).FEE_MAX()));

        Vat(bank).frob(rilk, self, int(200 * WAD), int(100 * WAD));

        // wait for some fees, then surplus auction
        skip(10);

        set_dxm('dam', RAY);
        uint sr1 = rico.balanceOf(self);
        Vow(bank).keep(single(rilk));
        uint sr2 = rico.balanceOf(self);
        assertGt(sr2, sr1);
    }

    // test_no_flap_pending_sin
    //   N/A keep always flops on debt and flaps on surplus, there's no debt queue

    // test_no_flap_nonzero_woe
    //   N/A this test is actually the same as test_no_flap_pending_sin

    // test_no_flap_pending_flop
    // test_no_flap_pending_heal
    //   N/A keep can flap while there's a pending flop auction if a surplus is generated
    //   uses ramps to rate limit both

    // test_no_surplus_after_good_flop
    //   N/A no flop

    // test_multiple_flop_dents
    //   N/A no standing auction mechanism, no dent, trades through AMM
}

// difference from dss: rico has bail instead of bark
// liquidations are done in one step, no standing auction kicked off
contract DssDogTest is DssJsTest {
    Usr gal;

    function _dog_setUp() internal {
        File(bank).file('ceil', bytes32(10000 * RAD));
        Vat(bank).filk(rilk, 'line', bytes32(10000 * RAD));

        risk.mint(self, 100000 * WAD);

        Vow(bank).keep(single(rilk));
    }

    modifier _dog_ { _dog_setUp(); _; }

    // create an urn
    function setUrn(uint ink, uint art) internal {
        Vat(bank).frob(rilk, self, int(ink), int(art));
    }

    function test_bark_basic() public _dog_ {
        uint init_ink = WAD;
        Vat(bank).filk(rilk, 'fee', bytes32(FEE_2X_ANN));
        File(bank).file('par', bytes32(RAY / 2000));
        setUrn(init_ink, 2000 * WAD);

        // make unsafe
        skip(BANKYEAR);

        // rico equivalent of bark, kick off the auction (which is filled instantly)
        Vat(bank).bail(rilk, self);

        uint art = _art(rilk, self);
        uint ink = _ink(rilk, self);
        assertLt(ink, init_ink);
        assertEq(art, 0);
    }

    function test_bark_not_unsafe() public _dog_ {
        File(bank).file('par', bytes32(RAY / 500));
        setUrn(WAD, 500 * WAD);

        // fee is RAY, no effect
        skip(BANKYEAR);

        vm.expectRevert(Vat.ErrSafeBail.selector);
        Vat(bank).bail(rilk, self);
    }

    function test_bark_dusty_vault() public {
        // difference from dss: no dog
        risk.mint(self, 200000 * WAD);

        uint dust = 200;
        Vat(bank).filk(rilk, 'dust', bytes32(dust * RAD));

        vm.expectRevert(Vat.ErrUrnDust.selector);
        Vat(bank).frob(rilk, self, int(200000 * WAD), int(199 * WAD));
    }

    // test_bark_partial_liquidation_dirt_exceeds_hole_to_avoid_dusty_remnant
    // test_bark_partial_liquidation_dirt_does_not_exceed_hole_if_remnant_is_nondusty
    // test_bark_partial_liquidation_Dirt_exceeds_Hole_to_avoid_dusty_remnant
    // test_bark_partial_liquidation_Dirt_does_not_exceed_Hole_if_remnant_is_nondusty
    // test_bark_dusty_vault_dusty_room
    // test_bark_do_not_create_dusty_auction_hole
    // test_bark_do_not_create_dusty_auction_Hole
    //   N/A no hole
}
