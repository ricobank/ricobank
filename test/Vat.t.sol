// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import { Ball } from '../src/ball.sol';
import { Flasher } from "./Flasher.sol";
import { RicoSetUp, Guy } from "./RicoHelper.sol";
import { OverrideableGem } from './mixin/OverrideableGem.sol';
import { Gem } from '../lib/gemfab/src/gem.sol';
import { Vat }  from '../src/vat.sol';
import { Vow }  from '../src/vow.sol';
import { Hook } from '../src/hook/hook.sol';
import '../src/mixin/math.sol';
import {File} from '../src/file.sol';
import {BankDiamond} from '../src/diamond.sol';
import {Bank} from '../src/bank.sol';

contract VatTest is Test, RicoSetUp {
    uint256 public init_join = 1000;
    uint stack = WAD * 10;
    bytes32[] ilks;
    address[] gems;
    uint256[] wads;
    Flasher public chap;
    address public achap;
    uint public constant flash_size = 100;
    uint public constant NO_CUT = type(uint256).max;

    function setUp() public {
        make_bank();
        init_gold();
        ilks.push(gilk);
        rico.approve(bank, type(uint256).max);
        chap = new Flasher(bank, arico, gilk);
        achap = address(chap);
        gold.mint(achap, 500 * WAD);
        gold.approve(achap, type(uint256).max);
        rico.approve(achap, type(uint256).max);
        gold.ward(achap, true);
        rico.ward(achap, true);

        gold.mint(bank, init_join * WAD);
    }

    modifier _chap_ {
        rico_mint(1, true); // needs an extra for rounding
        rico.transfer(achap, 1);
        _;
    }

    function test_frob_gas() public {
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        gold.mint(bank, 1);
        assertGt(gold.balanceOf(bank), 0);
        uint gas = gasleft();
        Vat(bank).frob(gilk, self, abi.encodePacked(WAD), int(WAD));
        check_gas(gas, 214614);
        gas = gasleft();
        Vat(bank).frob(gilk, self, abi.encodePacked(WAD), int(WAD));
        check_gas(gas, 34399);
    }

    function test_heal_gas() public {
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        Vat(bank).frob(gilk, self, abi.encodePacked(WAD), int(WAD));
        feedpush(grtag, bytes32(0), type(uint).max);
        Vat(bank).bail(gilk, self);

        uint gas = gasleft();
        Vat(bank).heal(1);
        check_gas(gas, 10351);
    }

    function test_drip_gas() public {
        uint gas = gasleft();
        Vat(bank).drip(gilk);
        check_gas(gas, 15346);

        Vat(bank).filk(gilk, 'fee', bytes32(2 * RAY));
        skip(1);
        Vat(bank).frob(gilk, self, abi.encodePacked(100 * WAD), int(50 * WAD));
        gas = gasleft();
        Vat(bank).drip(gilk);
        check_gas(gas, 37550);
    }

    function test_ilk_reset() public {
        vm.expectRevert(Vat.ErrMultiIlk.selector);
        Vat(bank).init(gilk, address(hook));
    }

    /* urn safety tests */

    // goldusd, par, and liqr all = 1 after set up
    function test_create_unsafe() public {
        // art should not exceed ink
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(gilk, address(this), abi.encodePacked(stack), int(stack) + 1);

        // art should not increase if iffy
        skip(1100);
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(gilk, address(this), abi.encodePacked(stack), int(1));
    }

    function test_safe_return_vals() public {
        Vat(bank).frob(gilk, address(this), abi.encodePacked(stack), int(stack));
        (Vat.Spot spot, uint rush, uint cut) = Vat(bank).safe(gilk, self);
        // position should be safe, just
        assertTrue(spot == Vat.Spot.Safe);
        // when safe rush should be 0
        assertEq(rush, 0);
        // have deposited 10 at a price of 1 with 1.0 cratio so cut should be 10
        assertEq(cut , RAD * 10);
        // drop price to 80%
        feedpush(grtag, bytes32(RAY * 4 / 5), block.timestamp + 1000);
        (spot, rush, cut) = Vat(bank).safe(gilk, self);
        // position should now be underwater
        assertTrue(spot == Vat.Spot.Sunk);
        // the rush should now be 1.25
        assertEq(rush, RAY * 5 / 4);
        // cut should be 80%
        assertEq(cut , RAD * 8);
        // wait longer than ttl so price feed is stale and expect iffy
        skip(1100);
        (spot, rush, cut) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Iffy);
    }

    function test_rack_puts_urn_underwater() public {
        // frob to exact edge
        Vat(bank).frob(gilk, address(this), abi.encodePacked(stack), int(stack));
        (Vat.Spot spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);

        // accrue some interest to sink
        skip(100);
        Vat(bank).drip(gilk);
        (spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Sunk);

        // can't refloat with neg quantity rate
        vm.expectRevert(Vat.ErrFeeMin.selector);
        Vat(bank).filk(gilk, 'fee', bytes32(RAY - 1));
    }

    function test_liqr_puts_urn_underwater() public {
        Vat(bank).frob(gilk, address(this), abi.encodePacked(stack), int(stack));
        (Vat.Spot spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);
        Vat(bank).filk(gilk, 'liqr', bytes32(RAY + 1000000));
        (spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Sunk);

        Vat(bank).filk(gilk, 'liqr', bytes32(RAY - 1000000));
        (spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);
    }

    function test_gold_crash_sinks_urn() public {
        Vat(bank).frob(gilk, address(this), abi.encodePacked(stack), int(stack));
        (Vat.Spot spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);

        feed.push(grtag, bytes32(RAY / 2), block.timestamp + 1000);
        (spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Sunk);

        feed.push(grtag, bytes32(RAY * 2), block.timestamp + 1000);
        (spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);
    }

    function test_time_makes_urn_iffy() public {
        Vat(bank).frob(gilk, address(this), abi.encodePacked(stack), int(stack));
        (Vat.Spot spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);

        // feed was set will ttl of now + 1000
        skip(1100);
        (spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Iffy);

        // without a drip an update should refloat urn
        feed.push(grtag, bytes32(RAY), block.timestamp + 1000);
        (spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);
    }

    function test_frob_refloat() public {
        Vat(bank).frob(gilk, address(this), abi.encodePacked(stack), int(stack));
        (Vat.Spot spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);

        feed.push(grtag, bytes32(RAY / 2), block.timestamp + 1000);
        (spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Sunk);

        Vat(bank).frob(gilk, address(this), abi.encodePacked(stack), int(0));
        (spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);
    }

    function test_increasing_risk_sunk_urn() public {
        Vat(bank).frob(gilk, address(this), abi.encodePacked(stack), int(stack));
        (Vat.Spot spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);

        feed.push(grtag, bytes32(RAY / 2), block.timestamp + 1000);
        (spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Sunk);

        //should always be able to decrease art
        Vat(bank).frob(gilk, address(this), abi.encodePacked(int(0)), int(-1));
        //should always be able to increase ink
        Vat(bank).frob(gilk, address(this), abi.encodePacked(int(1)), int(0));

        // should not be able to increase art of sunk urn
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(gilk, address(this), abi.encodePacked(int(10)), int(1));

        // should not be able to decrease ink of sunk urn
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(gilk, address(this), abi.encodePacked(int(-1)), int(1));
    }

    function test_increasing_risk_iffy_urn() public {
        Vat(bank).frob(gilk, address(this), abi.encodePacked(stack), int(10));
        (Vat.Spot spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);

        skip(1100);
        (spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Iffy);

        //should always be able to decrease art
        Vat(bank).frob(gilk, address(this), abi.encodePacked(int(0)), int(-1));
        //should always be able to increase ink
        Vat(bank).frob(gilk, address(this), abi.encodePacked(int(1)), int(0));

        // should not be able to increase art of iffy urn
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(gilk, address(this), abi.encodePacked(int(10)), int(1));

        // should not be able to decrease ink of iffy urn
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(gilk, address(this), abi.encodePacked(int(-1)), int(1));
    }

    function test_increasing_risk_safe_urn() public {
        Vat(bank).frob(gilk, address(this), abi.encodePacked(stack), int(10));
        (Vat.Spot spot,,) = Vat(bank).safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);

        //should always be able to decrease art
        Vat(bank).frob(gilk, address(this), abi.encodePacked(int(0)), int(-1));
        //should always be able to increase ink
        Vat(bank).frob(gilk, address(this), abi.encodePacked(int(1)), int(0));

        // should be able to increase art of iffy urn
        Vat(bank).frob(gilk, address(this), abi.encodePacked(int(0)), int(1));

        // should be able to decrease ink of iffy urn
        Vat(bank).frob(gilk, address(this), abi.encodePacked(int(-1)), int(0));
    }

    /* join/exit/flash tests */

    function test_rico_join_exit() public _chap_ {
        // give vat extra rico and gold to make sure it won't get withdrawn
        rico.mint(bank, 10000 * WAD);
        gold.mint(bank, 10000 * WAD);

        uint self_gold_bal0 = gold.balanceOf(self);
        uint self_rico_bal0 = rico.balanceOf(self);

        // revert for trying to join more gems than owned
        vm.expectRevert(Gem.ErrUnderflow.selector);
        Vat(bank).frob(gilk, self, abi.encodePacked(self_gold_bal0 + 1), 0);

        // revert for trying to exit too much rico
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(gilk, self, abi.encodePacked(int(10)), int(11));

        // revert for trying to exit gems from other users
        vm.expectRevert(Math.ErrUintUnder.selector);
        Vat(bank).frob(gilk, self, abi.encodePacked(int(-1)), 0);

        // gems are taken from user when joining, and rico given to user
        Vat(bank).frob(gilk, self, abi.encodePacked(stack), int(stack / 2));
        uint self_gold_bal1 = gold.balanceOf(self);
        uint self_rico_bal1 = rico.balanceOf(self);
        assertEq(self_gold_bal1 + stack, self_gold_bal0);
        assertEq(self_rico_bal1, self_rico_bal0 + stack / 2);

        // close, even without drip need 1 extra rico as rounding is in systems favour
        rico.mint(self, 1);
        Vat(bank).frob(gilk, self, abi.encodePacked(-int(stack)), -int(stack / 2));
        uint self_gold_bal2 = gold.balanceOf(self);
        uint self_rico_bal2 = rico.balanceOf(self);
        assertEq(self_gold_bal0, self_gold_bal2);
        assertEq(self_rico_bal0, self_rico_bal2);
    }

    function test_simple_rico_flash_mint() public _chap_ {
        uint initial_rico_supply = rico.totalSupply();

        bytes memory data = abi.encodeWithSelector(chap.nop.selector);
        Vat(bank).flash(achap, data);

        assertEq(rico.totalSupply(), initial_rico_supply);
        assertEq(rico.balanceOf(self), 0);
        assertEq(rico.balanceOf(bank), 0);
    }

    function test_rico_reentry() public _chap_ {
        bytes memory data = abi.encodeWithSelector(chap.reenter.selector, arico, flash_size * WAD);
        vm.expectRevert(Vat.ErrLock.selector);
        Vat(bank).flash(achap, data);
    }

    function test_rico_flash_over_max_supply_reverts() public _chap_ {
        rico.mint(self, type(uint256).max - stack - rico.totalSupply());
        bytes memory data = abi.encodeWithSelector(chap.nop.selector);
        vm.expectRevert(Gem.ErrOverflow.selector);
        Vat(bank).flash(achap, data);
    }

    function test_repayment_failure() public _chap_ {
        // remove any initial balance from chap
        uint chap_gold = gold.balanceOf(achap);
        uint chap_rico = rico.balanceOf(achap);
        chap.approve_sender(agold, chap_gold);
        chap.approve_sender(arico, chap_rico);
        gold.transferFrom(achap, self, chap_gold);
        rico.transferFrom(achap, self, chap_rico);

        // add rico and ensure fail if welching
        wads.push(init_join * WAD);
        gems.push(arico);
        bytes memory data0 = abi.encodeWithSelector(chap.welch.selector, gems, wads, 0);
        bytes memory data1 = abi.encodeWithSelector(chap.welch.selector, gems, wads, 1);
        vm.expectRevert(Gem.ErrUnderflow.selector);
        Vat(bank).flash(achap, data0);
        Vat(bank).flash(achap, data1);
    }

    function test_rico_handler_error() public _chap_ {
        bytes memory data = abi.encodeWithSelector(chap.failure.selector);
        vm.expectRevert(bytes4(keccak256(bytes('ErrBroken()'))));
        Vat(bank).flash(achap, data);
    }

    function test_rico_wind_up_and_release() public _chap_ {
        uint lock = 300 * WAD;
        uint draw = 200 * WAD;

        uint flash_gold1 = gold.balanceOf(achap);
        uint flash_rico1 = rico.balanceOf(achap);
        uint hook_gold1  = gold.balanceOf(address(hook));
        uint hook_rico1  = rico.balanceOf(address(hook));

        bytes memory data = abi.encodeWithSelector(chap.rico_lever.selector, agold, lock, draw);
        Vat(bank).flash(achap, data);

        uint ink = _ink(gilk, achap);
        uint art = _art(gilk, achap);
        assertEq(ink, lock);
        assertEq(art, draw);

        data = abi.encodeWithSelector(chap.rico_release.selector, agold, lock, draw);
        Vat(bank).flash(achap, data);

        assertEq(flash_gold1, gold.balanceOf(achap));
        assertEq(flash_rico1, rico.balanceOf(achap) + 1);
        assertEq(hook_gold1,  gold.balanceOf(address(hook)));
        assertEq(hook_rico1,  rico.balanceOf(address(hook)));
    }

    function test_init_conditions() public {
        assertEq(BankDiamond(bank).owner(), self);
    }

    function test_rejects_unsafe_frob() public {
        uint ink = _ink(gilk, self);
        uint art = _art(gilk, self);
        assertEq(ink, 0);
        assertEq(art, 0);
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(gilk, self, abi.encodePacked(int(0)), int(WAD));
    }

    function owed() internal returns (uint) {
        Vat(bank).drip(gilk);
        uint rack = Vat(bank).ilks(gilk).rack;
        uint art = _art(gilk, self);
        return rack * art;
    }

    function test_drip() public {
        Vat(bank).filk(gilk, 'fee', bytes32(RAY + RAY / 50));

        skip(1);
        Vat(bank).drip(gilk);
        Vat(bank).frob(gilk, self, abi.encodePacked(100 * WAD), int(50 * WAD));

        skip(1);
        uint debt0 = owed();

        skip(1);
        uint debt1 = owed();
        assertEq(debt1, debt0 + debt0 / 50);
    }

    function test_rest_monotonic() public {
        Vat(bank).filk(gilk, 'fee', bytes32(RAY + 2));
        Vat(bank).filk(gilk, 'dust', bytes32(0));
        Vat(bank).frob(gilk, self, abi.encodePacked(WAD + 1), int(WAD + 1));
        skip(1);
        Vat(bank).drip(gilk);
        assertEq(Vat(bank).rest(), 2 * WAD + 2);
        skip(1);
        Vat(bank).drip(gilk);
        assertGt(Vat(bank).rest(), 2 * WAD + 2);
    }

    function test_rest_drip_0() public {
        Vat(bank).filk(gilk, 'fee', bytes32(RAY + 1));
        Vat(bank).frob(gilk, self, abi.encodePacked(WAD), int(WAD));
        skip(1);
        Vat(bank).drip(gilk);
        assertEq(Vat(bank).rest(), WAD);

        skip(1);
        Vat(bank).drip(gilk);
        assertEq(Vat(bank).rest(), 2 * WAD);

        Vat(bank).filk(gilk, 'fee', bytes32(RAY));
        skip(1);
        Vat(bank).drip(gilk);
        assertEq(Vat(bank).rest(), 2 * WAD);

        Vat(bank).filk(gilk, 'fee', bytes32(3 * RAY));
        skip(1);
        Vat(bank).drip(gilk);
        assertEq(Vat(bank).rest(), 6 * WAD);
    }

    function test_rest_drip_toggle_ones() public {
        Vat(bank).filk(gilk, 'fee', bytes32(RAY));
        Vat(bank).filk(gilk, 'dust', bytes32(0));
        rico_mint(1, true);
        Vat(bank).frob(gilk, self, abi.encodePacked(int(1)), int(1));
        Vat(bank).frob(gilk, self, abi.encodePacked(-int(1)), -int(1));
        Vat(bank).drip(gilk);
        assertEq(Vat(bank).rest(), RAY);
        skip(1);
        Vat(bank).drip(gilk);
        assertEq(Vat(bank).rest(), 0);
    }

    function test_rest_drip_toggle_wads() public {
        Vat(bank).filk(gilk, 'fee', bytes32(RAY));
        Vat(bank).drip(gilk);
        Vat(bank).filk(gilk, 'fee', bytes32(RAY + 1));
        Vat(bank).filk(gilk, 'dust', bytes32(0));
        rico_mint(WAD, true);
        Vat(bank).frob(gilk, self, abi.encodePacked(WAD), int(WAD));
        skip(1);
        Vat(bank).drip(gilk);

        assertEq(Vat(bank).rest(), WAD);

        uint art = _art(gilk, self);
        Vat(bank).frob(gilk, self, abi.encodePacked(int(0)), -int(art));
        assertEq(Vat(bank).rest(), RAY);

        skip(1);
        Vat(bank).drip(gilk);
        assertEq(Vat(bank).rest(), 0);
    }

    function test_drip_neg_fee() public {
        vm.expectRevert(Vat.ErrFeeMin.selector);
        Vat(bank).filk(gilk, 'fee', bytes32(RAY / 2));
        skip(1);
        vm.expectRevert(Vat.ErrFeeRho.selector);
        Vat(bank).filk(gilk, 'fee', bytes32(RAY));
        Vat(bank).drip(gilk);
    }

    function test_feed_plot_safe() public {
        (Vat.Spot safe0,,) = Vat(bank).safe(gilk, self);
        assertEq(uint(safe0), uint(Vat.Spot.Safe));

        Vat(bank).frob(gilk, self, abi.encodePacked(100 * WAD), int(50 * WAD));

        (Vat.Spot safe1,,) = Vat(bank).safe(gilk, self);
        assertEq(uint(safe1), uint(Vat.Spot.Safe));


        uint ink = _ink(gilk, self);
        uint art = _art(gilk, self);
        assertEq(ink, 100 * WAD);
        assertEq(art, 50 * WAD);

        feed.push(grtag, bytes32(RAY), block.timestamp + 1000);

        (Vat.Spot safe2,,) = Vat(bank).safe(gilk, self);
        assertEq(uint(safe2), uint(Vat.Spot.Safe));

        feed.push(grtag, bytes32(RAY / 50), block.timestamp + 1000);

        (Vat.Spot safe3,,) = Vat(bank).safe(gilk, self);
        assertEq(uint(safe3), uint(Vat.Spot.Sunk));
    }

    function test_par() public {
        assertEq(Vat(bank).par(), RAY);
        Vat(bank).frob(gilk, self, abi.encodePacked(100 * WAD), int(50 * WAD));
        (Vat.Spot spot,,) = Vat(bank).safe(gilk, self);
        assertEq(uint(spot), uint(Vat.Spot.Safe));
        // par increase should increase collateral requirement
        File(bank).file('par', bytes32(RAY * 3));
        (Vat.Spot spot2,,) = Vat(bank).safe(gilk, self);
        assertEq(uint(spot2), uint(Vat.Spot.Sunk));
    }

    function test_frob_reentrancy_1() public {
        bytes32 htag = 'hgmrico';
        bytes32 hilk = 'hgm';
        uint dink = WAD;
        uint dart = WAD + 1;
        Gem hgm = Gem(address(new HackyGem(Frobber(self), bank, "hacky gem", "HGM")));
        HackyGem(address(hgm)).setargs(hilk, self, int(dink), int(dart));
        HackyGem(address(hgm)).setdepth(1);
        Vat(bank).init(hilk, address(hook));
        Vat(bank).filhi(hilk, 'gem', hilk, bytes32(bytes20(address(hgm))));
        Vat(bank).filhi(hilk, 'fsrc', hilk, bytes32(bytes20(address(mdn))));
        Vat(bank).filhi(hilk, 'ftag', hilk, htag);
 
        uint amt = WAD;

        hgm.mint(self, amt * 5);
        hgm.approve(bank, type(uint).max);
        make_feed(htag);
        Vat(bank).filk(hilk, 'line', bytes32(100000000 * RAD));
        File(bank).file('par', bytes32(RAY));
        feedpush(htag, bytes32(RAY), type(uint).max);
        uint fee = RAY + 1;
        Vat(bank).filk(hilk, bytes32('fee'), bytes32(fee)); 

        skip(1);
        // with one frob rest would be WAD + 1
        // should be double that with an extra recursive frob
        Vat(bank).drip(hilk);
        feedpush(htag, bytes32(RAY * 1000000), type(uint).max);
        Vat(bank).frob(hilk, self, abi.encodePacked(dink), int(dart));
        assertEq(Vat(bank).rest(), 2 * (WAD + 1));
    }

    function test_frob_reentrancy_toggle_rico() public {
        bytes32 htag = 'hgmrico';
        bytes32 hilk = 'hgm';
        uint dink = WAD;
        uint dart = WAD + 1;
        Gem hgm = Gem(address(new HackyGem(Frobber(self), bank, "hacky gem", "HGM")));
        HackyGem(address(hgm)).setargs(hilk, self, int(dink), int(dart));
        HackyGem(address(hgm)).setdepth(1);
        Vat(bank).init(hilk, address(hook));
        Vat(bank).filhi(hilk, 'gem', hilk, bytes32(bytes20(address(hgm))));
        Vat(bank).filhi(hilk, 'fsrc', hilk, bytes32(bytes20(address(mdn))));
        Vat(bank).filhi(hilk, 'ftag', hilk, htag);

        hgm.mint(self, dink * 1000);
        hgm.approve(bank, type(uint).max);
        make_feed(htag);
        Vat(bank).filk(hilk, 'line', bytes32(100000000 * RAD));
        File(bank).file('par', bytes32(RAY));
        feedpush(htag, bytes32(RAY), type(uint).max);
        uint fee = RAY + 1;
        Vat(bank).filk(hilk, bytes32('fee'), bytes32(fee)); 

        skip(1);
        // with one frob rest would be WAD + 1
        // should be double that with an extra recursive frob
        Vat(bank).drip(hilk);
        feedpush(htag, bytes32(RAY * 1000000), type(uint).max);
        // rico balance should underflow
        Vat(bank).frob(hilk, self, abi.encodePacked(dink), int(dart));
        assertEq(Vat(bank).rest(), 2 * (WAD + 1));


        // throw most out
        // minus one for rounding in system's favor
        rico.transfer(azero, rico.balanceOf(self) - 1);
        assertEq(rico.balanceOf(self), 1);
        HackyGem(address(hgm)).setdepth(1);
        // should fail because not enough left to send to vat
        vm.expectRevert(OverrideableGem.ErrUnderflow.selector);
        Vat(bank).frob(hilk, self, abi.encodePacked(dink), -int(dart));
    }

    function dofrob(bytes32 i, address u, int dink, int dart) public {
        Vat(bank).frob(i, u, abi.encodePacked(dink), dart);
    }

    function test_bail_reentrancy() public {
        // create a gem that re-bails on transfer
        // the re-bail should fail, because the first bail
        // wrote off the debt and an urn with 0 debt is safe
        bytes32 bailtag = 'bgmrico';
        bytes32 baililk = 'bgm';
        uint dink = WAD;
        uint dart = WAD;
        Gem bgm = Gem(address(new BailyGem(Bailer(self), bank, "baily gem", "BGM")));
        BailyGem(address(bgm)).setargs(baililk, self, -int(dink), -int(dart));
        Vat(bank).init(baililk, address(hook));
        Vat(bank).filhi(baililk, 'gem', baililk, bytes32(bytes20(address(bgm))));
        Vat(bank).filhi(baililk, 'fsrc', baililk, bytes32(bytes20(address(mdn))));
        Vat(bank).filhi(baililk, 'ftag', baililk, bailtag);

        bgm.mint(self, dink * 1000);
        bgm.approve(bank, type(uint).max);
        Vat(bank).filk(baililk, 'line', bytes32(100000000 * RAD));
        File(bank).file('par', bytes32(RAY));
        make_feed(bailtag);
        feedpush(bailtag, bytes32(RAY * 1000000), type(uint).max);
        Vat(bank).filk(baililk, 'chop', bytes32(RAY));

        Vat(bank).frob(baililk, self, abi.encodePacked(dink * 2), int(dart));
        BailyGem(address(bgm)).setdepth(1);
        feedpush(bailtag, bytes32(0), UINT256_MAX);
        // recursive call should be safe bail bc art == 0
        vm.expectRevert(Vat.ErrSafeBail.selector);
        Vat(bank).bail(baililk, self);
    }

    function dobail(bytes32 i, address u) public {
        Vat(bank).bail(i, u);
    }

    function test_frob_hook() public {
        FrobHook hook = new FrobHook();
        Vat(bank).filk(gilk, 'hook', bytes32(uint(bytes32(bytes20(address(hook))))));
        uint goldbefore = gold.balanceOf(self);
        bytes memory hookdata = abi.encodeCall(
            hook.frobhook,
            (self, gilk, self, abi.encodePacked(WAD), 0)
        );

        vm.expectCall(address(hook), hookdata);
        Vat(bank).frob(gilk, self, abi.encodePacked(WAD), 0);
        assertEq(gold.balanceOf(self), goldbefore);
    }

    function test_frob_hook_neg_dink() public {
        FrobHook hook = new FrobHook();
        Vat(bank).filk(gilk, 'hook', bytes32(uint(bytes32(bytes20(address(hook))))));
        uint goldbefore = gold.balanceOf(self);
        Vat(bank).frob(gilk, self, abi.encodePacked(WAD), 0);
        bytes memory hookdata = abi.encodeCall(
            hook.frobhook,
            (self, gilk, self, abi.encodePacked(-int(WAD)), 0)
        );

        vm.expectCall(address(hook), hookdata);
        Vat(bank).frob(gilk, self, abi.encodePacked(-int(WAD)), 0);
        assertEq(gold.balanceOf(self), goldbefore);
    }

    function test_bail_hook_1() public {
        // FrobHook's safehook returns a high number, so frob is safe
        FrobHook hook = new FrobHook();
        Vat(bank).filk(gilk, 'hook', bytes32(uint(bytes32(bytes20(address(hook))))));
        feedpush(grtag, bytes32(RAY), type(uint).max);
        Vat(bank).frob(gilk, self, abi.encodePacked(WAD), int(WAD));
        uint goldbefore = gold.balanceOf(self);

        // ZeroHook's safehook makes the urn unsafe
        ZeroHook zhook = new ZeroHook();
        Vat(bank).filk(gilk, 'hook', bytes32(uint(bytes32(bytes20(address(zhook))))));

        // check that bailhook called
        bytes memory hookdata = abi.encodeCall(
            zhook.bailhook,
            (gilk, self, WAD, self, UINT256_MAX, 0)
        );
        feedpush(grtag, bytes32(0), UINT256_MAX);
        vm.expectCall(address(zhook), hookdata);
        Vat(bank).bail(gilk, self);
        assertEq(gold.balanceOf(self), goldbefore);
    }

    function test_frob_err_ordering_1() public {
        Vat(bank).filk(gilk, 'fee', bytes32(2 * RAY));
        File(bank).file('ceil', bytes32(WAD - 1));
        Vat(bank).filk(gilk, 'dust', bytes32(RAD));
        skip(1);
        Vat(bank).drip(gilk);

        // ceily, not safe, wrong urn, dusty...should be ceily
        feedpush(grtag, bytes32(0), type(uint).max);
        vm.expectRevert(Vat.ErrDebtCeil.selector);
        Vat(bank).frob(gilk, bank, abi.encodePacked(WAD), int(WAD / 2));

        // non-ceily, should be dusty
        vm.expectRevert(Vat.ErrUrnDust.selector);
        Vat(bank).frob(gilk, bank, abi.encodePacked(WAD), int(WAD / 2 - 1));

        // non-dusty, should be unsafe
        Vat(bank).filk(gilk, 'dust', bytes32(RAD - RAY * 2));
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(gilk, bank, abi.encodePacked(WAD), int(WAD / 2 - 1));

        //safe, should be wrong urn
        feedpush(grtag, bytes32(RAY), type(uint).max);
        vm.expectRevert(Vat.ErrWrongUrn.selector);
        Vat(bank).frob(gilk, bank, abi.encodePacked(WAD), int(WAD / 2 - 1));

        // raising ceil should fix ceil
        File(bank).file('ceil', bytes32(WAD));
        Vat(bank).frob(gilk, self, abi.encodePacked(WAD * 2), int(WAD / 2));
    }

    function test_frob_err_ordering_darts() public {
        Vat(bank).filk(gilk, 'fee', bytes32(2 * RAY));
        File(bank).file('ceil', bytes32(WAD));
        Vat(bank).filk(gilk, 'dust', bytes32(RAD));
        skip(1);
        Vat(bank).drip(gilk);
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);

        address amdn = address(mdn);
        gold.mint(amdn, 1000 * WAD);
        vm.startPrank(amdn);
        gold.approve(bank, 1000 * WAD);
        Vat(bank).frob(gilk, address(mdn), abi.encodePacked(WAD * 2), int(WAD / 2));
        rico.transfer(self, 100);
        vm.stopPrank();

        // bypasses most checks when dart <= 0
        feedpush(grtag, bytes32(0), type(uint).max);
        File(bank).file('ceil', bytes32(0));
        vm.expectRevert(Vat.ErrDebtCeil.selector);
        Vat(bank).frob(gilk, amdn, abi.encodePacked(WAD), int(1));
        Vat(bank).frob(gilk, amdn, abi.encodePacked(WAD), int(0));
        vm.expectRevert(Vat.ErrUrnDust.selector);
        Vat(bank).frob(gilk, amdn, abi.encodePacked(WAD), -int(1));
    }

    function test_frob_err_ordering_dinks() public {
        Vat(bank).filk(gilk, 'fee', bytes32(2 * RAY));
        File(bank).file('ceil', bytes32(WAD));
        Vat(bank).filk(gilk, 'dust', bytes32(RAD));
        skip(1);
        Vat(bank).drip(gilk);
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);

        address amdn = address(mdn);
        gold.mint(amdn, 1000 * WAD);
        vm.startPrank(amdn);
        gold.approve(bank, 1000 * WAD);
        Vat(bank).frob(gilk, address(mdn), abi.encodePacked(WAD * 2), int(WAD / 2));
        vm.stopPrank();

        // bypasses most checks when dink >= 0
        feedpush(grtag, bytes32(0), type(uint).max);
        File(bank).file('ceil', bytes32(0));
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(gilk, amdn, abi.encodePacked(-int(1)), int(0));
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        vm.expectRevert(Vat.ErrWrongUrn.selector);
        Vat(bank).frob(gilk, amdn, abi.encodePacked(-int(1)), int(0));
        feedpush(grtag, bytes32(0), type(uint).max);
        // doesn't care when ink >= 0
        Vat(bank).frob(gilk, amdn, abi.encodePacked(int(0)), int(0));
        Vat(bank).frob(gilk, amdn, abi.encodePacked(int(1)), int(0));
    }

    function test_frob_err_ordering_dinks_darts() public {
        Vat(bank).filk(gilk, 'fee', bytes32(2 * RAY));
        File(bank).file('ceil', bytes32(WAD * 10000));
        Vat(bank).filk(gilk, 'dust', bytes32(RAD));
        skip(1);
        Vat(bank).drip(gilk);
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);

        address amdn = address(mdn);
        gold.mint(amdn, 1000 * WAD);
        vm.startPrank(amdn);
        gold.approve(bank, 1000 * WAD);
        Vat(bank).frob(gilk, address(mdn), abi.encodePacked(WAD * 2), int(WAD / 2));
        // 2 for accumulated debt, 1 for rounding
        rico.transfer(self, 3);
        vm.stopPrank();

        // bypasses most checks when dink >= 0
        feedpush(grtag, bytes32(0), type(uint).max);
        File(bank).file('ceil', bytes32(WAD * 10000));

        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(gilk, amdn, abi.encodePacked(-int(1)), int(1));
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        vm.expectRevert(Vat.ErrWrongUrn.selector);
        Vat(bank).frob(gilk, amdn, abi.encodePacked(-int(1)), int(1));
        feedpush(grtag, bytes32(0), type(uint).max);
        // doesn't care when ink >= 0
        Vat(bank).frob(gilk, amdn, abi.encodePacked(int(0)), int(0));
        vm.expectRevert(Vat.ErrUrnDust.selector);
        Vat(bank).frob(gilk, amdn, abi.encodePacked(int(1)), int(-1));
        Vat(bank).filk(gilk, 'dust', bytes32(RAD / 2));
        Vat(bank).frob(gilk, amdn, abi.encodePacked(int(1)), int(-1));
    }

    function test_frob_ilk_uninitialized() public {
        feedpush(grtag, bytes32(0), type(uint).max);
        vm.expectRevert(Vat.ErrIlkInit.selector);
        Vat(bank).frob('hello', self, abi.encodePacked(WAD), int(WAD));
    }

    function test_debt_not_normalized() public {
        Vat(bank).drip(gilk);
        Vat(bank).filk(gilk, 'fee', bytes32(2 * RAY));
        Vat(bank).frob(gilk, self, abi.encodePacked(WAD), int(WAD));
        assertEq(Vat(bank).debt(), WAD);
        skip(1);
        Vat(bank).drip(gilk);
        assertEq(Vat(bank).debt(), WAD * 2);
    }

    function test_dtab_not_normalized() public {
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        Vat(bank).drip(gilk);
        Vat(bank).filk(gilk, 'fee', bytes32(2 * RAY));
        Vat(bank).frob(gilk, self, abi.encodePacked(WAD), int(WAD));
        assertEq(Vat(bank).debt(), WAD);
        skip(1);
        Vat(bank).drip(gilk);

        // dtab > 0
        uint ricobefore = rico.balanceOf(self);
        Vat(bank).frob(gilk, self, abi.encodePacked(WAD), int(WAD));
        uint ricoafter = rico.balanceOf(self);
        assertEq(ricoafter, ricobefore + WAD * 2);

        // dtab < 0
        ricobefore = rico.balanceOf(self);
        Vat(bank).frob(gilk, self, abi.encodePacked(int(0)), -int(WAD));
        ricoafter = rico.balanceOf(self);
        assertEq(ricoafter, ricobefore - (WAD * 2 + 1));
    }

    function test_drip_all_rest_1() public {
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        Vat(bank).filk(gilk, 'fee', bytes32(RAY * 3 / 2));
        // raise rack to 1.5
        skip(1);
        // now frob 1, so debt is 1 * RAY
        // and rest is 0.5 * RAY
        Vat(bank).drip(gilk);
        Vat(bank).frob(gilk, self, abi.encodePacked(int(1)), int(1));
        assertEq(Vat(bank).rest(), RAY / 2);
        assertEq(Vat(bank).debt(), 1);
        // need to wait for drip to do anything...
        Vat(bank).drip(gilk);
        assertEq(Vat(bank).debt(), 1);
        assertEq(Vat(bank).rest(), RAY / 2);

        // frob again so rest reaches RAY
        Vat(bank).frob(gilk, self, abi.encodePacked(int(1)), int(1));
        assertEq(Vat(bank).debt(), 2);
        assertEq(Vat(bank).rest(), RAY);

        // so regardless of fee next drip should drip 1
        Vat(bank).filk(gilk, 'fee', bytes32(RAY));
        skip(1);
        Vat(bank).drip(gilk);
        assertEq(Vat(bank).debt(), 3);
        assertEq(Vat(bank).rest(), 0);
        assertEq(rico.totalSupply(), 3);
    }

    function test_frobhook_only_checks_dink() public {
        Guy guy = new Guy(bank);
        OnlyInkHook inkhook = new OnlyInkHook();
        Vat(bank).filk(gilk, 'hook', bytes32(uint(bytes32(bytes20(address(inkhook))))));

        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        gold.mint(address(guy), 1000 * WAD);
        vm.expectRevert(Vat.ErrWrongUrn.selector);
        guy.frob(gilk, self, abi.encodePacked(int(0)), int(WAD));
    }

    function test_gethi() public {
        bytes32 val;
        val = Vat(bank).gethi(gilk, 'fsrc', gilk);
        assertEq(address(bytes20(val)), self);
        val = Vat(bank).gethi(gilk, 'ftag', gilk);
        assertEq(val, grtag);
 
        vm.expectRevert(Bank.ErrWrongKey.selector);
        Vat(bank).gethi(gilk, 'oh', gilk);
    }

    function test_bail_drips() public {
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        Vat(bank).frob(gilk, self, abi.encodePacked(WAD), int(WAD));
        skip(BANKYEAR);

        uint prevrack = Vat(bank).ilks(gilk).rack;
        feedpush(grtag, bytes32(0), type(uint).max);
        Vat(bank).bail(gilk, self);
        assertGt(Vat(bank).ilks(gilk).rack, prevrack);
    }


    // make sure ink and bail decode properly
    function test_bail_return_value() public {
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        Vat(bank).frob(gilk, self, abi.encodePacked(WAD), int(WAD));
        feedpush(grtag, bytes32(0), type(uint).max);
        bytes memory sold = Vat(bank).bail(gilk, self);
        assertEq(sold.length, 32);
    }

    function test_ink_return_value() public {
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        Vat(bank).frob(gilk, self, abi.encodePacked(WAD), int(WAD));
        bytes memory ink = Vat(bank).ink(gilk, self);
        assertEq(ink.length, 32);
    }

}

contract OnlyInkHook is Hook {
    function frobhook(
        address, bytes32, address, bytes calldata dink, int
    ) pure external returns (bool safer) {
        return int(uint(bytes32(dink[:32]))) >= 0; 
    }
    function bailhook(
        bytes32 i, address u, uint bill, address keeper, uint rush, uint cut
    ) external returns (bytes memory) {}
    function safehook(
        bytes32, address
    ) pure external returns (uint, uint){return(uint(10 ** 18 * 10 ** 27), type(uint256).max);}
    function ink(bytes32, address) external pure returns (bytes memory) {
        return abi.encode(uint(0));
    }
}

contract FrobHook is Hook {
    function frobhook(
        address, bytes32, address, bytes calldata dink, int dart
    ) pure external returns (bool safer) {
        return int(uint(bytes32(dink[:32]))) >= 0 && dart <= 0; 
    }
    function bailhook(
        bytes32 i, address u, uint bill, address keeper, uint rush, uint cut
    ) external returns (bytes memory) {}
    function safehook(
        bytes32, address
    ) pure external returns (uint, uint){return(uint(10 ** 18 * 10 ** 27), type(uint256).max);}
    function ink(bytes32, address) external pure returns (bytes memory) {
        return abi.encode(uint(0));
    }
}
contract ZeroHook is Hook {
    function frobhook(
        address sender, bytes32 i, address u, bytes calldata dink, int dart
    ) external returns (bool safer) {}
    function bailhook(
        bytes32 i, address u, uint bill, address keeper, uint rush, uint cut
    ) external returns (bytes memory) {}
    function safehook(
        bytes32, address
    ) pure external returns (uint, uint){return(uint(0), type(uint256).max);}
    function ink(bytes32, address) external pure returns (bytes memory) {
        return abi.encode(uint(0));
    }
}

interface Frobber {
    function dofrob(bytes32 i, address u, int dink, int dart) external;
}

contract HackyGem is OverrideableGem {
    uint depth;
    bytes32 i;
    address u;
    int dink;
    int dart;
    Frobber frobber;
    address payable bank;

    constructor(Frobber _frobber, address payable _bank, bytes32 name, bytes32 symbol) OverrideableGem(name, symbol) {
        bank = _bank;
        frobber = _frobber;
    }

    function setdepth(uint _depth) public {
        depth = _depth;
    }

    function setargs(bytes32 _i, address _u, int _dink, int _dart) public {
        i = _i;
        u = _u;
        dink = _dink;
        dart = _dart;
    }

    function transferFrom(address src, address dst, uint wad) public payable virtual override returns (bool ok) {

        if (depth > 0) {
            depth--;
            frobber.dofrob(i, u, dink, dart);
        }

        unchecked {
            ok              = true;
            balanceOf[dst] += wad;
            uint256 prevB   = balanceOf[src];
            balanceOf[src]  = prevB - wad;
            uint256 prevA   = allowance[src][msg.sender];

            emit Transfer(src, dst, wad);

            if ( prevA != type(uint256).max ) {
                allowance[src][msg.sender] = prevA - wad;
                if( prevA < wad ) {
                    revert ErrUnderflow();
                }
            }

            if( prevB < wad ) {
                revert ErrUnderflow();
            }
        }
    }
}

interface Bailer {
    function dobail(bytes32 i, address u) external;
}

contract BailyGem is OverrideableGem {
    address payable bank;
    uint depth;
    bytes32 i;
    address u;
    int dink;
    int dart;
    Bailer bailer;

    constructor(Bailer _bailer, address payable _bank, bytes32 name, bytes32 symbol) OverrideableGem(name, symbol) {
        bank = _bank;
        bailer = _bailer;
    }

    function setdepth(uint _depth) public {
        depth = _depth;
    }

    function setargs(bytes32 _i, address _u, int _dink, int _dart) public {
        i = _i;
        u = _u;
        dink = _dink;
        dart = _dart;
    }

    function transfer(address dst, uint wad)
      payable external virtual override returns (bool ok)
    {
        if (depth > 0) {
            depth--;
            bailer.dobail(i, u);
        }

        unchecked {
            ok = true;
            uint256 prev = balanceOf[msg.sender];
            balanceOf[msg.sender] = prev - wad;
            balanceOf[dst]       += wad;
            emit Transfer(msg.sender, dst, wad);
            if( prev < wad ) {
                revert ErrUnderflow();
            }
        }
    }
}
