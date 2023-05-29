// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import { Ball } from '../src/ball.sol';
import { Flasher } from "./Flasher.sol";
import { RicoSetUp, Guy } from "./RicoHelper.sol";
import { OverrideableGem } from './mixin/OverrideableGem.sol';
import { Gem } from '../lib/gemfab/src/gem.sol';
import { Vat }  from '../src/vat.sol';
import { Hook } from '../src/hook/hook.sol';
import '../src/mixin/lock.sol';
import '../src/mixin/math.sol';
import { ERC20Hook, NO_CUT } from '../src/hook/ERC20hook.sol';

contract VatTest is Test, RicoSetUp {
    uint256 public init_join = 1000;
    uint stack = WAD * 10;
    bytes32[] ilks;
    address[] gems;
    uint256[] wads;
    Flasher public chap;
    address public achap;
    uint public constant flash_size = 100;

    function setUp() public {
        make_bank();
        init_gold();
        ilks.push(gilk);
        rico.approve(ahook, type(uint256).max);
        chap = new Flasher(avat, arico, gilk, address(hook));
        achap = address(chap);
        gold.mint(achap, 500 * WAD);
        gold.approve(achap, type(uint256).max);
        rico.approve(achap, type(uint256).max);
        gold.ward(achap, true);
        rico.ward(achap, true);

        gold.mint(address(hook), init_join * WAD);
    }

    modifier _chap_ {
        rico_mint(1, true); // needs an extra for rounding
        rico.transfer(achap, 1);
        _;
    }

    function test_frob_gas() public {
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        gold.mint(address(hook), 1);
        assertGt(gold.balanceOf(address(hook)), 0);
        uint gas = gasleft();
        vat.frob(gilk, self, abi.encodePacked(WAD), int(WAD));
        check_gas(gas, 204598);
        gas = gasleft();
        vat.frob(gilk, self, abi.encodePacked(WAD), int(WAD));
        check_gas(gas, 26883);
    }

    function test_grab_gas() public {
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        vat.frob(gilk, self, abi.encodePacked(WAD), int(WAD));
        uint gas = gasleft();
        vat.grab(gilk, self, self, no_rush, NO_CUT);
        check_gas(gas, 72194);
    }

    function test_heal_gas() public {
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        vat.frob(gilk, self, abi.encodePacked(WAD), int(WAD));
        feedpush(grtag, bytes32(0), type(uint).max);
        vat.grab(gilk, self, self, no_rush, NO_CUT);

        uint gas = gasleft();
        vat.heal(WAD - 1);
        check_gas(gas, 7520);
    }

    function test_drip_gas() public {
        uint gas = gasleft();
        vat.drip(gilk);
        check_gas(gas, 12097);

        vat.filk(gilk, 'fee', 2 * RAY);
        skip(1);
        vat.frob(gilk, self, abi.encodePacked(100 * WAD), int(50 * WAD));
        gas = gasleft();
        vat.drip(gilk);
        check_gas(gas, 14902);
    }

    function test_ilk_reset() public {
        vm.expectRevert(Vat.ErrMultiIlk.selector);
        vat.init(gilk, address(hook));
    }

    /* urn safety tests */

    // goldusd, par, and liqr all = 1 after set up
    function test_create_unsafe() public {
        // art should not exceed ink
        vm.expectRevert(Vat.ErrNotSafe.selector);
        vat.frob(gilk, address(this), abi.encodePacked(stack), int(stack) + 1);

        // art should not increase if iffy
        skip(1100);
        vm.expectRevert(Vat.ErrNotSafe.selector);
        vat.frob(gilk, address(this), abi.encodePacked(stack), int(1));
    }

    function test_safe_return_vals() public {
        vat.frob(gilk, address(this), abi.encodePacked(stack), int(stack));
        (Vat.Spot spot, uint rush, uint cut) = vat.safe(gilk, self);
        // position should be safe, just
        assertTrue(spot == Vat.Spot.Safe);
        // when safe rush should be 0
        assertEq(rush, 0);
        // have deposited 10 at a price of 1 with 1.0 cratio so cut should be 10
        assertEq(cut , RAD * 10);
        // drop price to 80%
        feedpush(grtag, bytes32(RAY * 4 / 5), block.timestamp + 1000);
        (spot, rush, cut) = vat.safe(gilk, self);
        // position should now be underwater
        assertTrue(spot == Vat.Spot.Sunk);
        // the rush should now be 1.25
        assertEq(rush, RAY * 5 / 4);
        // cut should be 80%
        assertEq(cut , RAD * 8);
        // beyond DASH the rush factor should be clipped
        uint dash = vat.DASH();
        feedpush(grtag, bytes32(RAY / 10), block.timestamp + 1000);
        (spot, rush, cut) = vat.safe(gilk, self);
        assertEq(rush, dash);
        // wait longer than ttl so price feed is stale and expect iffy
        skip(1100);
        (spot, rush, cut) = vat.safe(gilk, self);
        assertTrue(spot == Vat.Spot.Iffy);
    }

    function test_rack_puts_urn_underwater() public {
        // frob to exact edge
        vat.frob(gilk, address(this), abi.encodePacked(stack), int(stack));
        (Vat.Spot spot,,) = vat.safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);

        // accrue some interest to sink
        skip(100);
        vat.drip(gilk);
        (spot,,) = vat.safe(gilk, self);
        assertTrue(spot == Vat.Spot.Sunk);

        // can't refloat with neg quantity rate
        vm.expectRevert(Vat.ErrFeeMin.selector);
        vat.filk(gilk, 'fee', RAY - 1);
    }

    function test_liqr_puts_urn_underwater() public {
        vat.frob(gilk, address(this), abi.encodePacked(stack), int(stack));
        (Vat.Spot spot,,) = vat.safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);
        vat.filk(gilk, 'liqr', RAY + 1000000);
        (spot,,) = vat.safe(gilk, self);
        assertTrue(spot == Vat.Spot.Sunk);

        vat.filk(gilk, 'liqr', RAY - 1000000);
        (spot,,) = vat.safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);
    }

    function test_gold_crash_sinks_urn() public {
        vat.frob(gilk, address(this), abi.encodePacked(stack), int(stack));
        (Vat.Spot spot,,) = vat.safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);

        feed.push(grtag, bytes32(RAY / 2), block.timestamp + 1000);
        (spot,,) = vat.safe(gilk, self);
        assertTrue(spot == Vat.Spot.Sunk);

        feed.push(grtag, bytes32(RAY * 2), block.timestamp + 1000);
        (spot,,) = vat.safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);
    }

    function test_time_makes_urn_iffy() public {
        vat.frob(gilk, address(this), abi.encodePacked(stack), int(stack));
        (Vat.Spot spot,,) = vat.safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);

        // feed was set will ttl of now + 1000
        skip(1100);
        (spot,,) = vat.safe(gilk, self);
        assertTrue(spot == Vat.Spot.Iffy);

        // without a drip an update should refloat urn
        feed.push(grtag, bytes32(RAY), block.timestamp + 1000);
        (spot,,) = vat.safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);
    }

    function test_frob_refloat() public {
        vat.frob(gilk, address(this), abi.encodePacked(stack), int(stack));
        (Vat.Spot spot,,) = vat.safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);

        feed.push(grtag, bytes32(RAY / 2), block.timestamp + 1000);
        (spot,,) = vat.safe(gilk, self);
        assertTrue(spot == Vat.Spot.Sunk);

        vat.frob(gilk, address(this), abi.encodePacked(stack), int(0));
        (spot,,) = vat.safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);
    }

    function test_increasing_risk_sunk_urn() public {
        vat.frob(gilk, address(this), abi.encodePacked(stack), int(stack));
        (Vat.Spot spot,,) = vat.safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);

        feed.push(grtag, bytes32(RAY / 2), block.timestamp + 1000);
        (spot,,) = vat.safe(gilk, self);
        assertTrue(spot == Vat.Spot.Sunk);

        //should always be able to decrease art
        vat.frob(gilk, address(this), abi.encodePacked(int(0)), int(-1));
        //should always be able to increase ink
        vat.frob(gilk, address(this), abi.encodePacked(int(1)), int(0));

        // should not be able to increase art of sunk urn
        vm.expectRevert(Vat.ErrNotSafe.selector);
        vat.frob(gilk, address(this), abi.encodePacked(int(10)), int(1));

        // should not be able to decrease ink of sunk urn
        vm.expectRevert(Vat.ErrNotSafe.selector);
        vat.frob(gilk, address(this), abi.encodePacked(int(-1)), int(1));
    }

    function test_increasing_risk_iffy_urn() public {
        vat.frob(gilk, address(this), abi.encodePacked(stack), int(10));
        (Vat.Spot spot,,) = vat.safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);

        skip(1100);
        (spot,,) = vat.safe(gilk, self);
        assertTrue(spot == Vat.Spot.Iffy);

        //should always be able to decrease art
        vat.frob(gilk, address(this), abi.encodePacked(int(0)), int(-1));
        //should always be able to increase ink
        vat.frob(gilk, address(this), abi.encodePacked(int(1)), int(0));

        // should not be able to increase art of iffy urn
        vm.expectRevert(Vat.ErrNotSafe.selector);
        vat.frob(gilk, address(this), abi.encodePacked(int(10)), int(1));

        // should not be able to decrease ink of iffy urn
        vm.expectRevert(Vat.ErrNotSafe.selector);
        vat.frob(gilk, address(this), abi.encodePacked(int(-1)), int(1));
    }

    function test_increasing_risk_safe_urn() public {
        vat.frob(gilk, address(this), abi.encodePacked(stack), int(10));
        (Vat.Spot spot,,) = vat.safe(gilk, self);
        assertTrue(spot == Vat.Spot.Safe);

        //should always be able to decrease art
        vat.frob(gilk, address(this), abi.encodePacked(int(0)), int(-1));
        //should always be able to increase ink
        vat.frob(gilk, address(this), abi.encodePacked(int(1)), int(0));

        // should be able to increase art of iffy urn
        vat.frob(gilk, address(this), abi.encodePacked(int(0)), int(1));

        // should be able to decrease ink of iffy urn
        vat.frob(gilk, address(this), abi.encodePacked(int(-1)), int(0));
    }

    /* join/exit/flash tests */

    function test_rico_join_exit() public _chap_ {
        // give vat extra rico and gold to make sure it won't get withdrawn
        rico.mint(avat, 10000 * WAD);
        gold.mint(avat, 10000 * WAD);

        uint self_gold_bal0 = gold.balanceOf(self);
        uint self_rico_bal0 = rico.balanceOf(self);

        // revert for trying to join more gems than owned
        vm.expectRevert(Gem.ErrUnderflow.selector);
        vat.frob(gilk, self, abi.encodePacked(self_gold_bal0 + 1), 0);

        // revert for trying to exit too much rico
        vm.expectRevert(Vat.ErrNotSafe.selector);
        vat.frob(gilk, self, abi.encodePacked(int(10)), int(11));

        // revert for trying to exit gems from other users
        vm.expectRevert(Math.ErrUintUnder.selector);
        vat.frob(gilk, self, abi.encodePacked(int(-1)), 0);

        // gems are taken from user when joining, and rico given to user
        vat.frob(gilk, self, abi.encodePacked(stack), int(stack / 2));
        uint self_gold_bal1 = gold.balanceOf(self);
        uint self_rico_bal1 = rico.balanceOf(self);
        assertEq(self_gold_bal1 + stack, self_gold_bal0);
        assertEq(self_rico_bal1, self_rico_bal0 + stack / 2);

        // close, even without drip need 1 extra rico as rounding is in systems favour
        rico.mint(self, 1);
        vat.frob(gilk, self, abi.encodePacked(-int(stack)), -int(stack / 2));
        uint self_gold_bal2 = gold.balanceOf(self);
        uint self_rico_bal2 = rico.balanceOf(self);
        assertEq(self_gold_bal0, self_gold_bal2);
        assertEq(self_rico_bal0, self_rico_bal2);
    }

    function test_simple_rico_flash_mint() public _chap_ {
        uint initial_rico_supply = rico.totalSupply();

        bytes memory data = abi.encodeWithSelector(chap.nop.selector);
        vat.flash(achap, data);

        assertEq(rico.totalSupply(), initial_rico_supply);
        assertEq(rico.balanceOf(self), 0);
        assertEq(rico.balanceOf(ahook), 0);
    }

    function test_rico_reentry() public _chap_ {
        bytes memory data = abi.encodeWithSelector(chap.reenter.selector, arico, flash_size * WAD);
        vm.expectRevert(Lock.ErrLock.selector);
        vat.flash(achap, data);
    }

    function test_borrow_gem_after_rico() public _chap_ {
        uint flash_gold1 = gold.balanceOf(achap);
        uint flash_rico1 = rico.balanceOf(achap);
        uint hook_gold1  = gold.balanceOf(ahook);
        uint vat_rico1   = rico.balanceOf(avat);
        uint rico_supply = rico.totalSupply();

        bytes memory data = abi.encodeWithSelector(chap.borrow_gem_after_rico.selector, agold, stack);
        vat.flash(achap, data);

        assertEq(flash_gold1, gold.balanceOf(achap));
        assertEq(flash_rico1, rico.balanceOf(achap));
        assertEq(hook_gold1,  gold.balanceOf(ahook));
        assertEq(vat_rico1,   rico.balanceOf(avat));
        assertEq(rico_supply, rico.totalSupply());
    }

    function test_rico_flash_over_max_supply_reverts() public _chap_ {
        rico.mint(self, type(uint256).max - stack - rico.totalSupply());
        bytes memory data = abi.encodeWithSelector(chap.nop.selector);
        vm.expectRevert(Gem.ErrOverflow.selector);
        vat.flash(achap, data);
    }

    function test_repayment_failure() public _chap_ {
        // remove any initial balance from chap
        uint chap_gold = gold.balanceOf(achap);
        uint chap_rico = rico.balanceOf(achap);
        chap.approve_sender(agold, chap_gold);
        chap.approve_sender(arico, chap_rico);
        gold.transferFrom(achap, self, chap_gold);
        rico.transferFrom(achap, self, chap_rico);

        // add gold and ensure fail if welching
        gems.push(agold);
        wads.push(init_join * WAD);
        bytes memory data0 = abi.encodeWithSelector(chap.welch.selector, gems, wads, 0);
        bytes memory data1 = abi.encodeWithSelector(chap.welch.selector, gems, wads, 1);
        vm.expectRevert(Gem.ErrUnderflow.selector);
        hook.flash(gems, wads, achap, data0);
        // not welching should pass
        hook.flash(gems, wads, achap, data1);

        // and rico
        gems.pop();
        gems.push(arico);
        data0 = abi.encodeWithSelector(chap.welch.selector, gems, wads, 0);
        data1 = abi.encodeWithSelector(chap.welch.selector, gems, wads, 1);
        vm.expectRevert(Gem.ErrUnderflow.selector);
        vat.flash(achap, data0);
        vat.flash(achap, data1);
    }

    function test_revert_wrong_joy() public _chap_ {
        bytes memory data = abi.encodeWithSelector(chap.nop.selector);
        gems.push(arisk);
        wads.push(stack);
        vm.expectRevert(ERC20Hook.ErrLoanArgs.selector);
        hook.flash(gems, wads, achap, data);
    }

    function test_rico_handler_error() public _chap_ {
        bytes memory data = abi.encodeWithSelector(chap.failure.selector);
        vm.expectRevert(bytes4(keccak256(bytes('ErrBroken()'))));
        vat.flash(achap, data);
    }

    function test_gem_handler_error() public _chap_ {
        bytes memory data = abi.encodeWithSelector(chap.failure.selector);
        gems.push(agold);
        wads.push(stack);
        vm.expectRevert(bytes4(keccak256(bytes('ErrBroken()'))));
        hook.flash(gems, wads, achap, data);
    }

    function test_rico_wind_up_and_release() public _chap_ {
        uint lock = 300 * WAD;
        uint draw = 200 * WAD;

        uint flash_gold1 = gold.balanceOf(achap);
        uint flash_rico1 = rico.balanceOf(achap);
        uint hook_gold1  = gold.balanceOf(address(hook));
        uint hook_rico1  = rico.balanceOf(address(hook));

        bytes memory data = abi.encodeWithSelector(chap.rico_lever.selector, agold, lock, draw);
        vat.flash(achap, data);

        uint ink = _ink(gilk, achap);
        uint art = _art(gilk, achap);
        assertEq(ink, lock);
        assertEq(art, draw);

        data = abi.encodeWithSelector(chap.rico_release.selector, agold, lock, draw);
        vat.flash(achap, data);

        assertEq(flash_gold1, gold.balanceOf(achap));
        assertEq(flash_rico1, rico.balanceOf(achap) + 1);
        assertEq(hook_gold1,  gold.balanceOf(address(hook)));
        assertEq(hook_rico1,  rico.balanceOf(address(hook)));
    }

    function test_gem_simple_flash() public _chap_ {
        uint chap_gold1 = gold.balanceOf(achap);
        uint vat_gold1 = gold.balanceOf(avat);

        bytes memory data = abi.encodeWithSelector(chap.approve_hook.selector, agold, flash_size * WAD);
        gems.push(agold);
        wads.push(flash_size * WAD);
        hook.flash(gems, wads, achap, data);

        assertEq(gold.balanceOf(achap), chap_gold1);
        assertEq(gold.balanceOf(avat), vat_gold1);
    }

    function test_gem_flash_insufficient_approval() public _chap_ {
        bytes memory data = abi.encodeWithSelector(chap.approve_hook.selector, agold, flash_size * WAD - 1);
        gems.push(agold);
        wads.push(flash_size * WAD);
        vm.expectRevert(Gem.ErrUnderflow.selector);
        hook.flash(gems, wads, achap, data);
    }

    function test_gem_flash_insufficient_assets() public _chap_ {
        bytes memory data = abi.encodeWithSelector(chap.approve_hook.selector, agold, type(uint256).max);
        gems.push(agold);
        wads.push(init_join * WAD);
        hook.flash(gems, wads, achap, data);
        wads.pop();
        wads.push(init_join * WAD + 1);
        vm.expectRevert(Gem.ErrUnderflow.selector);
        hook.flash(gems, wads, achap, data);
    }

    function test_gem_flash_unsupported_gem() public _chap_ {
        bytes memory data = abi.encodeWithSelector(chap.approve_hook.selector, agold, type(uint256).max);
        gems.push(agold);
        wads.push(init_join * WAD);
        hook.flash(gems, wads, achap, data);
        hook.list(agold, false);
        vm.expectRevert(ERC20Hook.ErrLoanArgs.selector);
        hook.flash(gems, wads, achap, data);
    }

    function test_gem_flasher_failure() public _chap_ {
        bytes memory data = abi.encodeWithSelector(chap.failure.selector);
        gems.push(agold);
        wads.push(init_join * WAD);
        vm.expectRevert(bytes4(keccak256(bytes('ErrBroken()'))));
        hook.flash(gems, wads, achap, data);
    }

    function test_gem_flash_reentry() public _chap_ {
        bytes memory data = abi.encodeWithSelector(chap.reenter.selector, agold, flash_size * WAD);
        gems.push(agold);
        wads.push(init_join * WAD);
        vm.expectRevert(Lock.ErrLock.selector);
        hook.flash(gems, wads, achap, data);
    }

    function test_gem_jump_wind_up_and_release() public _chap_ {
        uint lock = 1000 * WAD;
        uint draw = 500 * WAD;
        uint chap_gold1 = gold.balanceOf(achap);
        uint chap_rico1 = rico.balanceOf(achap);
        uint hook_gold1 = gold.balanceOf(address(hook));
        uint hook_rico1 = rico.balanceOf(address(hook));

        // chap had 500 gold, double it with 500 loan repaid by buying with borrowed rico
        bytes memory data = abi.encodeWithSelector(chap.gem_lever.selector, agold, lock, draw);
        gems.push(agold);
        wads.push(draw);
        hook.flash(gems, wads, achap, data);
        uint ink = _ink(gilk, achap);
        uint art = _art(gilk, achap);
        assertEq(ink, lock);
        assertEq(art, draw);

        data = abi.encodeWithSelector(chap.gem_release.selector, agold, lock, draw);
        hook.flash(gems, wads, achap, data);
        assertEq(gold.balanceOf(achap), chap_gold1);
        assertEq(rico.balanceOf(achap) + 1, chap_rico1);
        assertEq(gold.balanceOf(address(hook)), hook_gold1);
        assertEq(rico.balanceOf(address(hook)), hook_rico1);
    }

    function test_init_conditions() public {
        assertEq(vat.wards(self), true);
    }

    function test_rejects_unsafe_frob() public {
        uint ink = _ink(gilk, self);
        uint art = _art(gilk, self);
        assertEq(ink, 0);
        assertEq(art, 0);
        vm.expectRevert(Vat.ErrNotSafe.selector);
        vat.frob(gilk, self, abi.encodePacked(int(0)), int(WAD));
    }

    function owed() internal returns (uint) {
        vat.drip(gilk);
        (,uint rack,,,,,,,) = vat.ilks(gilk);
        uint art = _art(gilk, self);
        return rack * art;
    }

    function test_drip() public {
        vat.filk(gilk, 'fee', RAY + RAY / 50);

        skip(1);
        vat.drip(gilk);
        vat.frob(gilk, self, abi.encodePacked(100 * WAD), int(50 * WAD));

        skip(1);
        uint debt0 = owed();

        skip(1);
        uint debt1 = owed();
        assertEq(debt1, debt0 + debt0 / 50);
    }

    function test_rest_monotonic() public {
        vat.filk(gilk, 'fee', RAY + 2);
        vat.filk(gilk, 'dust', 0);
        vat.frob(gilk, self, abi.encodePacked(WAD + 1), int(WAD + 1));
        skip(1);
        vat.drip(gilk);
        assertEq(vat.rest(), 2 * WAD + 2);
        skip(1);
        vat.drip(gilk);
        assertGt(vat.rest(), 2 * WAD + 2);
    }

    function test_rest_drip_0() public {
        vat.filk(gilk, 'fee', RAY + 1);
        vat.frob(gilk, self, abi.encodePacked(WAD), int(WAD));
        skip(1);
        vat.drip(gilk);
        assertEq(vat.rest(), WAD);

        skip(1);
        vat.drip(gilk);
        assertEq(vat.rest(), 2 * WAD);

        vat.filk(gilk, 'fee', RAY);
        skip(1);
        vat.drip(gilk);
        assertEq(vat.rest(), 2 * WAD);

        vat.filk(gilk, 'fee', 3 * RAY);
        skip(1);
        vat.drip(gilk);
        assertEq(vat.rest(), 6 * WAD);
    }

    function test_rest_drip_toggle_ones() public {
        vat.filk(gilk, 'fee', RAY);
        vat.filk(gilk, 'dust', 0);
        rico_mint(1, true);
        vat.frob(gilk, self, abi.encodePacked(int(1)), int(1));
        vat.frob(gilk, self, abi.encodePacked(-int(1)), -int(1));
        vat.drip(gilk);
        assertEq(vat.rest(), RAY);
        skip(1);
        vat.drip(gilk);
        assertEq(vat.rest(), 0);
    }

    function test_rest_drip_toggle_wads() public {
        vat.filk(gilk, 'fee', RAY);
        vat.drip(gilk);
        vat.filk(gilk, 'fee', RAY + 1);
        vat.filk(gilk, 'dust', 0);
        rico_mint(WAD, true);
        vat.frob(gilk, self, abi.encodePacked(WAD), int(WAD));
        skip(1);
        vat.drip(gilk);

        assertEq(vat.rest(), WAD);

        uint art = _art(gilk, self);
        vat.frob(gilk, self, abi.encodePacked(int(0)), -int(art));
        assertEq(vat.rest(), RAY);

        skip(1);
        vat.drip(gilk);
        assertEq(vat.rest(), 0);
    }

    function test_drip_neg_fee() public {
        vm.expectRevert(Vat.ErrFeeMin.selector);
        vat.filk(gilk, 'fee', RAY / 2);
        skip(1);
        vm.expectRevert(Vat.ErrFeeRho.selector);
        vat.filk(gilk, 'fee', RAY);
        vat.drip(gilk);
    }

    function test_feed_plot_safe() public {
        (Vat.Spot safe0,,) = vat.safe(gilk, self);
        assertEq(uint(safe0), uint(Vat.Spot.Safe));

        vat.frob(gilk, self, abi.encodePacked(100 * WAD), int(50 * WAD));

        (Vat.Spot safe1,,) = vat.safe(gilk, self);
        assertEq(uint(safe1), uint(Vat.Spot.Safe));


        uint ink = _ink(gilk, self);
        uint art = _art(gilk, self);
        assertEq(ink, 100 * WAD);
        assertEq(art, 50 * WAD);

        feed.push(grtag, bytes32(RAY), block.timestamp + 1000);

        (Vat.Spot safe2,,) = vat.safe(gilk, self);
        assertEq(uint(safe2), uint(Vat.Spot.Safe));

        feed.push(grtag, bytes32(RAY / 50), block.timestamp + 1000);

        (Vat.Spot safe3,,) = vat.safe(gilk, self);
        assertEq(uint(safe3), uint(Vat.Spot.Sunk));
    }

    function test_par() public {
        assertEq(vat.par(), RAY);
        vat.frob(gilk, self, abi.encodePacked(100 * WAD), int(50 * WAD));
        (Vat.Spot spot,,) = vat.safe(gilk, self);
        assertEq(uint(spot), uint(Vat.Spot.Safe));
        // par increase should increase collateral requirement
        vat.prod(RAY * 3);
        (Vat.Spot spot2,,) = vat.safe(gilk, self);
        assertEq(uint(spot2), uint(Vat.Spot.Sunk));
    }

    function test_frob_reentrancy_1() public {
        bytes32 htag = 'hgmrico';
        bytes32 hilk = 'hgm';
        uint dink = WAD;
        uint dart = WAD + 1;
        Gem hgm = Gem(address(new HackyGem(Frobber(self), vat, "hacky gem", "HGM")));
        HackyGem(address(hgm)).setargs(hilk, self, int(dink), int(dart));
        HackyGem(address(hgm)).setdepth(1);
        hook.wire(hilk, address(hgm), address(mdn), htag);
        uint amt = WAD;

        hgm.mint(self, amt * 5);
        hgm.approve(address(hook), type(uint).max);
        make_feed(htag);
        vat.init(hilk, address(hook));
        vat.filk(hilk, 'line', 100000000 * RAD);
        vat.prod(RAY);
        feedpush(htag, bytes32(RAY), type(uint).max);
        uint fee = RAY + 1;
        vat.filk(hilk, bytes32('fee'),  fee); 

        skip(1);
        // with one frob rest would be WAD + 1
        // should be double that with an extra recursive frob
        vat.drip(hilk);
        feedpush(htag, bytes32(RAY * 1000000), type(uint).max);
        vat.frob(hilk, self, abi.encodePacked(dink), int(dart));
        assertEq(vat.rest(), 2 * (WAD + 1));
    }

    function test_frob_reentrancy_toggle_rico() public {
        bytes32 htag = 'hgmrico';
        bytes32 hilk = 'hgm';
        uint dink = WAD;
        uint dart = WAD + 1;
        Gem hgm = Gem(address(new HackyGem(Frobber(self), vat, "hacky gem", "HGM")));
        HackyGem(address(hgm)).setargs(hilk, self, int(dink), int(dart));
        HackyGem(address(hgm)).setdepth(1);
        hook.wire(hilk, address(hgm), address(mdn), htag);

        hgm.mint(self, dink * 1000);
        hgm.approve(address(hook), type(uint).max);
        make_feed(htag);
        vat.init(hilk, address(hook));
        vat.filk(hilk, 'line', 100000000 * RAD);
        vat.prod(RAY);
        feedpush(htag, bytes32(RAY), type(uint).max);
        uint fee = RAY + 1;
        vat.filk(hilk, bytes32('fee'),  fee); 

        skip(1);
        // with one frob rest would be WAD + 1
        // should be double that with an extra recursive frob
        vat.drip(hilk);
        feedpush(htag, bytes32(RAY * 1000000), type(uint).max);
        // rico balance should underflow
        vat.frob(hilk, self, abi.encodePacked(dink), int(dart));
        assertEq(vat.rest(), 2 * (WAD + 1));


        // throw most out
        // minus one for rounding in system's favor
        rico.transfer(azero, rico.balanceOf(self) - 1);
        assertEq(rico.balanceOf(self), 1);
        HackyGem(address(hgm)).setdepth(1);
        // should fail because not enough left to send to vat
        vm.expectRevert(OverrideableGem.ErrUnderflow.selector);
        vat.frob(hilk, self, abi.encodePacked(dink), -int(dart));
    }

    function dofrob(bytes32 i, address u, int dink, int dart) public {
        vat.frob(i, u, abi.encodePacked(dink), dart);
    }

    function test_grab_reentrancy() public {
        bytes32 grabtag = 'ggmrico';
        bytes32 grabilk = 'ggm';
        uint dink = WAD;
        uint dart = WAD;
        Gem ggm = Gem(address(new GrabbyGem(Grabber(self), vat, "grabby gem", "GGM")));
        GrabbyGem(address(ggm)).setargs(grabilk, self, -int(dink), -int(dart));
        hook.wire(grabilk, address(ggm), address(mdn), grabtag);

        ggm.mint(self, dink * 1000);
        ggm.approve(address(hook), type(uint).max);
        vat.init(grabilk, address(hook));
        vat.filk(grabilk, 'line', 100000000 * RAD);
        vat.prod(RAY);
        make_feed(grabtag);
        feedpush(grabtag, bytes32(RAY * 1000000), type(uint).max);
        vat.filk(grabilk, 'chop', RAY);

        vat.frob(grabilk, self, abi.encodePacked(dink * 2), int(dart));
        GrabbyGem(address(ggm)).setdepth(1);
        // additional grab will not impact vat
        vat.grab(grabilk, self, self, no_rush, NO_CUT);
        assertEq(vat.sin(self), WAD * RAY);
    }

    function dograb(bytes32 i, address u) public {
        vat.grab(i, u, self, no_rush, NO_CUT);
    }

    function test_frob_hook() public {
        FrobHook hook = new FrobHook();
        vat.filk(gilk, 'hook', uint(bytes32(bytes20(address(hook)))));
        uint goldbefore = gold.balanceOf(self);
        bytes memory hookdata = abi.encodeCall(
            hook.frobhook,
            (self, gilk, self, abi.encodePacked(WAD), 0)
        );

        vm.expectCall(address(hook), hookdata);
        vat.frob(gilk, self, abi.encodePacked(WAD), 0);
        assertEq(gold.balanceOf(self), goldbefore);
    }

    function test_frob_hook_neg_dink() public {
        FrobHook hook = new FrobHook();
        vat.filk(gilk, 'hook', uint(bytes32(bytes20(address(hook)))));
        uint goldbefore = gold.balanceOf(self);
        vat.frob(gilk, self, abi.encodePacked(WAD), 0);
        bytes memory hookdata = abi.encodeCall(
            hook.frobhook,
            (self, gilk, self, abi.encodePacked(-int(WAD)), 0)
        );

        vm.expectCall(address(hook), hookdata);
        vat.frob(gilk, self, abi.encodePacked(-int(WAD)), 0);
        assertEq(gold.balanceOf(self), goldbefore);
    }

    function test_grab_hook_1() public {
        // FrobHook's safehook returns a high number, so frob is safe
        FrobHook hook = new FrobHook();
        vat.filk(gilk, 'hook', uint(bytes32(bytes20(address(hook)))));
        feedpush(grtag, bytes32(RAY), type(uint).max);
        vat.frob(gilk, self, abi.encodePacked(WAD), int(WAD));
        uint goldbefore = gold.balanceOf(self);

        // ZeroHook's safehook makes the urn unsafe
        ZeroHook zhook = new ZeroHook();
        vat.filk(gilk, 'hook', uint(bytes32(bytes20(address(zhook)))));

        // check that grabhook called
        bytes memory hookdata = abi.encodeCall(
            zhook.grabhook,
            (self, gilk, self, WAD, WAD, self, no_rush, NO_CUT)
        );
        vm.expectCall(address(zhook), hookdata);
        vat.grab(gilk, self, self, no_rush, NO_CUT);
        assertEq(gold.balanceOf(self), goldbefore);
    }

    function test_frob_err_ordering_1() public {
        vat.filk(gilk, 'fee', 2 * RAY);
        vat.file('ceil', WAD - 1);
        vat.filk(gilk, 'dust', RAD);
        skip(1);
        vow.drip(gilk);

        // ceily, not safe, wrong urn, dusty...should be ceily
        feedpush(grtag, bytes32(0), type(uint).max);
        vm.expectRevert(Vat.ErrDebtCeil.selector);
        vat.frob(gilk, avox, abi.encodePacked(WAD), int(WAD / 2));

        // non-ceily, should be dusty
        vm.expectRevert(Vat.ErrUrnDust.selector);
        vat.frob(gilk, avox, abi.encodePacked(WAD), int(WAD / 2 - 1));

        // non-dusty, should be unsafe
        vat.filk(gilk, 'dust', RAD - RAY * 2);
        vm.expectRevert(Vat.ErrNotSafe.selector);
        vat.frob(gilk, avox, abi.encodePacked(WAD), int(WAD / 2 - 1));

        //safe, should be wrong urn
        feedpush(grtag, bytes32(RAY), type(uint).max);
        vm.expectRevert(Vat.ErrWrongUrn.selector);
        vat.frob(gilk, avox, abi.encodePacked(WAD), int(WAD / 2 - 1));

        // raising ceil should fix ceil
        vat.file('ceil', WAD);
        vat.frob(gilk, self, abi.encodePacked(WAD * 2), int(WAD / 2));
    }

    function test_frob_err_ordering_darts() public {
        vat.filk(gilk, 'fee', 2 * RAY);
        vat.file('ceil', WAD);
        vat.filk(gilk, 'dust', RAD);
        skip(1);
        vow.drip(gilk);
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);

        address amdn = address(mdn);
        gold.mint(amdn, 1000 * WAD);
        vm.startPrank(amdn);
        gold.approve(ahook, 1000 * WAD);
        vat.frob(gilk, address(mdn), abi.encodePacked(WAD * 2), int(WAD / 2));
        rico.transfer(self, 100);
        vm.stopPrank();

        // bypasses most checks when dart <= 0
        feedpush(grtag, bytes32(0), type(uint).max);
        vat.file('ceil', 0);
        vm.expectRevert(Vat.ErrDebtCeil.selector);
        vat.frob(gilk, amdn, abi.encodePacked(WAD), int(1));
        vat.frob(gilk, amdn, abi.encodePacked(WAD), int(0));
        vm.expectRevert(Vat.ErrUrnDust.selector);
        vat.frob(gilk, amdn, abi.encodePacked(WAD), -int(1));
    }

    function test_frob_err_ordering_dinks() public {
        vat.filk(gilk, 'fee', 2 * RAY);
        vat.file('ceil', WAD);
        vat.filk(gilk, 'dust', RAD);
        skip(1);
        vow.drip(gilk);
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);

        address amdn = address(mdn);
        gold.mint(amdn, 1000 * WAD);
        vm.startPrank(amdn);
        gold.approve(ahook, 1000 * WAD);
        vat.frob(gilk, address(mdn), abi.encodePacked(WAD * 2), int(WAD / 2));
        vm.stopPrank();

        // bypasses most checks when dink >= 0
        feedpush(grtag, bytes32(0), type(uint).max);
        vat.file('ceil', 0);
        vm.expectRevert(Vat.ErrNotSafe.selector);
        vat.frob(gilk, amdn, abi.encodePacked(-int(1)), int(0));
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        vm.expectRevert(Vat.ErrWrongUrn.selector);
        vat.frob(gilk, amdn, abi.encodePacked(-int(1)), int(0));
        feedpush(grtag, bytes32(0), type(uint).max);
        // doesn't care when ink >= 0
        vat.frob(gilk, amdn, abi.encodePacked(int(0)), int(0));
        vat.frob(gilk, amdn, abi.encodePacked(int(1)), int(0));
    }

    function test_frob_err_ordering_dinks_darts() public {
        vat.filk(gilk, 'fee', 2 * RAY);
        vat.file('ceil', WAD * 10000);
        vat.filk(gilk, 'dust', RAD);
        skip(1);
        vow.drip(gilk);
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);

        address amdn = address(mdn);
        gold.mint(amdn, 1000 * WAD);
        vm.startPrank(amdn);
        gold.approve(ahook, 1000 * WAD);
        vat.frob(gilk, address(mdn), abi.encodePacked(WAD * 2), int(WAD / 2));
        // 2 for accumulated debt, 1 for rounding
        rico.transfer(self, 3);
        vm.stopPrank();

        // bypasses most checks when dink >= 0
        feedpush(grtag, bytes32(0), type(uint).max);
        vat.file('ceil', WAD * 10000);

        vm.expectRevert(Vat.ErrNotSafe.selector);
        vat.frob(gilk, amdn, abi.encodePacked(-int(1)), int(1));
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        vm.expectRevert(Vat.ErrWrongUrn.selector);
        vat.frob(gilk, amdn, abi.encodePacked(-int(1)), int(1));
        feedpush(grtag, bytes32(0), type(uint).max);
        // doesn't care when ink >= 0
        vat.frob(gilk, amdn, abi.encodePacked(int(0)), int(0));
        vm.expectRevert(Vat.ErrUrnDust.selector);
        vat.frob(gilk, amdn, abi.encodePacked(int(1)), int(-1));
        vat.filk(gilk, 'dust', RAD / 2);
        vat.frob(gilk, amdn, abi.encodePacked(int(1)), int(-1));
    }

    function test_frob_ilk_uninitialized() public {
        feedpush(grtag, bytes32(0), type(uint).max);
        vm.expectRevert(Vat.ErrIlkInit.selector);
        vat.frob('hello', self, abi.encodePacked(WAD), int(WAD));
    }

    function test_debt_not_normalized() public {
        vow.drip(gilk);
        vat.filk(gilk, 'fee', 2 * RAY);
        vat.frob(gilk, self, abi.encodePacked(WAD), int(WAD));
        assertEq(vat.debt(), WAD);
        skip(1);
        vow.drip(gilk);
        assertEq(vat.debt(), WAD * 2);
    }

    function test_dtab_not_normalized() public {
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        vow.drip(gilk);
        vat.filk(gilk, 'fee', 2 * RAY);
        vat.frob(gilk, self, abi.encodePacked(WAD), int(WAD));
        assertEq(vat.debt(), WAD);
        skip(1);
        vow.drip(gilk);

        // dtab > 0
        uint ricobefore = rico.balanceOf(self);
        vat.frob(gilk, self, abi.encodePacked(WAD), int(WAD));
        uint ricoafter = rico.balanceOf(self);
        assertEq(ricoafter, ricobefore + WAD * 2);

        // dtab < 0
        ricobefore = rico.balanceOf(self);
        vat.frob(gilk, self, abi.encodePacked(int(0)), -int(WAD));
        ricoafter = rico.balanceOf(self);
        assertEq(ricoafter, ricobefore - (WAD * 2 + 1));
    }

    function test_drip_all_rest_1() public {
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        vat.filk(gilk, 'fee', RAY * 3 / 2);
        // raise rack to 1.5
        skip(1);
        // now frob 1, so debt is 1 * RAY
        // and rest is 0.5 * RAY
        vat.drip(gilk);
        vat.frob(gilk, self, abi.encodePacked(int(1)), int(1));
        assertEq(vat.rest(), RAY / 2);
        assertEq(vat.debt(), 1);
        // need to wait for drip to do anything...
        vow.drip(gilk);
        assertEq(vat.debt(), 1);
        assertEq(vat.rest(), RAY / 2);

        // frob again so rest reaches RAY
        vat.frob(gilk, self, abi.encodePacked(int(1)), int(1));
        assertEq(vat.debt(), 2);
        assertEq(vat.rest(), RAY);

        // so regardless of fee next drip should drip 1
        vat.filk(gilk, 'fee', RAY);
        skip(1);
        vat.drip(gilk);
        assertEq(vat.debt(), 3);
        assertEq(vat.rest(), 0);
        assertEq(rico.totalSupply(), 3);
    }

    function test_frobhook_only_checks_dink() public {
        Guy guy = new Guy(avat, avow);
        OnlyInkHook inkhook = new OnlyInkHook();
        vat.filk(gilk, 'hook', uint(bytes32(bytes20(address(inkhook)))));

        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        gold.mint(address(guy), 1000 * WAD);
        vm.expectRevert(Vat.ErrWrongUrn.selector);
        guy.frob(gilk, self, abi.encodePacked(int(0)), int(WAD));
    }

}

contract OnlyInkHook is Hook {
    function frobhook(
        address, bytes32, address, bytes calldata dink, int
    ) pure external returns (bool safer) {
        return int(uint(bytes32(dink[:32]))) >= 0; 
    }
    function grabhook(
        address vow, bytes32 i, address u, uint art, uint bill, address keeper, uint rush, uint cut
    ) external {}
    function safehook(
        bytes32, address
    ) pure external returns (uint, uint){return(uint(10 ** 18 * 10 ** 27), type(uint256).max);}
}

contract FrobHook is Hook {
    function frobhook(
        address, bytes32, address, bytes calldata dink, int dart
    ) pure external returns (bool safer) {
        return int(uint(bytes32(dink[:32]))) >= 0 && dart <= 0; 
    }
    function grabhook(
        address vow, bytes32 i, address u, uint art, uint bill, address keeper, uint rush, uint cut
    ) external {}
    function safehook(
        bytes32, address
    ) pure external returns (uint, uint){return(uint(10 ** 18 * 10 ** 27), type(uint256).max);}
}
contract ZeroHook is Hook {
    function frobhook(
        address sender, bytes32 i, address u, bytes calldata dink, int dart
    ) external returns (bool safer) {}
    function grabhook(
        address vow, bytes32 i, address u, uint art, uint bill, address keeper, uint rush, uint cut
    ) external {}
    function safehook(
        bytes32, address
    ) pure external returns (uint, uint){return(uint(0), type(uint256).max);}
}

interface Frobber {
    function dofrob(bytes32 i, address u, int dink, int dart) external;
}

contract HackyGem is OverrideableGem {
    Vat vat;
    uint depth;
    bytes32 i;
    address u;
    int dink;
    int dart;
    Frobber frobber;

    constructor(Frobber _frobber, Vat _vat, bytes32 name, bytes32 symbol) OverrideableGem(name, symbol) {
        vat = _vat;
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

interface Grabber {
    function dograb(bytes32 i, address u) external;
}

contract GrabbyGem is OverrideableGem {
    Vat vat;
    uint depth;
    bytes32 i;
    address u;
    int dink;
    int dart;
    Grabber grabber;

    constructor(Grabber _grabber, Vat _vat, bytes32 name, bytes32 symbol) OverrideableGem(name, symbol) {
        vat = _vat;
        grabber = _grabber;
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
            grabber.dograb(i, u);
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
