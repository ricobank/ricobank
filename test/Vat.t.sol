// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import "forge-std/Test.sol";

import { Ball } from '../src/ball.sol';
import { Flasher } from "./Flasher.sol";
import { RicoSetUp } from "./RicoHelper.sol";
import { Gem } from '../lib/gemfab/src/gem.sol';
import { Vat } from '../src/vat.sol';
import '../src/mixin/lock.sol';
import '../src/mixin/math.sol';

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
        rico.approve(address(flow), type(uint256).max);
        chap = new Flasher(avat, arico, gilk);
        achap = address(chap);
        gold.mint(achap, 500 * WAD);
        gold.approve(achap, type(uint256).max);
        rico.approve(achap, type(uint256).max);
        gold.ward(achap, true);
        rico.ward(achap, true);

        gold.mint(avat, init_join * WAD);
        rico.mint(achap, 1);  // needs an extra for rounding
    }

    function test_ilk_reset() public {
        vm.expectRevert(Vat.ErrMultiIlk.selector);
        vat.init(gilk, address(gold), self, gtag);
    }

    /* urn safety tests */

    // goldusd, par, and liqr all = 1 after set up
    function test_create_unsafe() public {
        // art should not exceed ink
        vm.expectRevert(Vat.ErrNotSafe.selector);
        vat.frob(gilk, address(this), int(stack), int(stack) + 1);

        // art should not increase if iffy
        skip(1100);
        vm.expectRevert(Vat.ErrNotSafe.selector);
        vat.frob(gilk, address(this), int(stack), int(1));
    }

    function test_rack_puts_urn_underwater() public {
        // frob to exact edge
        vat.frob(gilk, address(this), int(stack), int(stack));
        assertTrue(vat.safe(gilk, self) == Vat.Spot.Safe);

        // accrue some interest to sink
        skip(100);
        vat.drip(gilk);
        assertTrue(vat.safe(gilk, self) == Vat.Spot.Sunk);

        // can't refloat with neg quantity rate
        vm.expectRevert(Vat.ErrFeeMin.selector);
        vat.filk(gilk, 'fee', RAY - 1);
    }

    function test_liqr_puts_urn_underwater() public {
        vat.frob(gilk, address(this), int(stack), int(stack));
        assertTrue(vat.safe(gilk, self) == Vat.Spot.Safe);
        vat.filk(gilk, 'liqr', RAY - 1000000);
        assertTrue(vat.safe(gilk, self) == Vat.Spot.Sunk);

        vat.filk(gilk, 'liqr', RAY + 1000000);
        assertTrue(vat.safe(gilk, self) == Vat.Spot.Safe);
    }

    function test_gold_crash_sinks_urn() public {
        vat.frob(gilk, address(this), int(stack), int(stack));
        assertTrue(vat.safe(gilk, self) == Vat.Spot.Safe);

        feed.push(gtag, bytes32(RAY / 2), block.timestamp + 1000);
        assertTrue(vat.safe(gilk, self) == Vat.Spot.Sunk);

        feed.push(gtag, bytes32(RAY * 2), block.timestamp + 1000);
        assertTrue(vat.safe(gilk, self) == Vat.Spot.Safe);
    }

    function test_time_makes_urn_iffy() public {
        vat.frob(gilk, address(this), int(stack), int(stack));
        assertTrue(vat.safe(gilk, self) == Vat.Spot.Safe);

        // feed was set will ttl of now + 1000
        skip(1100);
        assertTrue(vat.safe(gilk, self) == Vat.Spot.Iffy);

        // without a drip an update should refloat urn
        feed.push(gtag, bytes32(RAY), block.timestamp + 1000);
        assertTrue(vat.safe(gilk, self) == Vat.Spot.Safe);
    }

    function test_frob_refloat() public {
        vat.frob(gilk, address(this), int(stack), int(stack));
        assertTrue(vat.safe(gilk, self) == Vat.Spot.Safe);

        feed.push(gtag, bytes32(RAY / 2), block.timestamp + 1000);
        assertTrue(vat.safe(gilk, self) == Vat.Spot.Sunk);

        vat.frob(gilk, address(this), int(stack), int(0));
        assertTrue(vat.safe(gilk, self) == Vat.Spot.Safe);
    }

    function test_increasing_risk_sunk_urn() public {
        vat.frob(gilk, address(this), int(stack), int(stack));
        assertTrue(vat.safe(gilk, self) == Vat.Spot.Safe);

        feed.push(gtag, bytes32(RAY / 2), block.timestamp + 1000);
        assertTrue(vat.safe(gilk, self) == Vat.Spot.Sunk);

        //should always be able to decrease art
        vat.frob(gilk, address(this), int(0), int(-1));
        //should always be able to increase ink
        vat.frob(gilk, address(this), int(1), int(0));

        // should not be able to increase art of sunk urn
        vm.expectRevert(Vat.ErrNotSafe.selector);
        vat.frob(gilk, address(this), int(10), int(1));

        // should not be able to decrease ink of sunk urn
        vm.expectRevert(Vat.ErrNotSafe.selector);
        vat.frob(gilk, address(this), int(-1), int(1));
    }

    function test_increasing_risk_iffy_urn() public {
        vat.frob(gilk, address(this), int(stack), int(10));
        assertTrue(vat.safe(gilk, self) == Vat.Spot.Safe);

        skip(1100);
        assertTrue(vat.safe(gilk, self) == Vat.Spot.Iffy);

        //should always be able to decrease art
        vat.frob(gilk, address(this), int(0), int(-1));
        //should always be able to increase ink
        vat.frob(gilk, address(this), int(1), int(0));

        // should not be able to increase art of iffy urn
        vm.expectRevert(Vat.ErrNotSafe.selector);
        vat.frob(gilk, address(this), int(10), int(1));

        // should not be able to decrease ink of iffy urn
        vm.expectRevert(Vat.ErrNotSafe.selector);
        vat.frob(gilk, address(this), int(-1), int(1));
    }

    function test_increasing_risk_safe_urn() public {
        vat.frob(gilk, address(this), int(stack), int(10));
        assertTrue(vat.safe(gilk, self) == Vat.Spot.Safe);

        //should always be able to decrease art
        vat.frob(gilk, address(this), int(0), int(-1));
        //should always be able to increase ink
        vat.frob(gilk, address(this), int(1), int(0));

        // should be able to increase art of iffy urn
        vat.frob(gilk, address(this), int(0), int(1));

        // should be able to decrease ink of iffy urn
        vat.frob(gilk, address(this), int(-1), int(0));
    }

    /* join/exit/flash tests */

    function test_rico_join_exit() public {
        // give vat extra rico and gold to make sure it won't get withdrawn
        rico.mint(avat, 10000 * WAD);
        gold.mint(avat, 10000 * WAD);

        uint self_gold_bal0 = gold.balanceOf(self);
        uint self_rico_bal0 = rico.balanceOf(self);

        // revert for trying to join more gems than owned
        vm.expectRevert(Gem.ErrUnderflow.selector);
        vat.frob(gilk, self, int(init_mint * WAD + 1), 0);

        // revert for trying to exit too much rico
        vm.expectRevert(Vat.ErrNotSafe.selector);
        vat.frob(gilk, self, int(10), int(11));

        // revert for trying to exit gems from other users
        vm.expectRevert(Math.ErrIntUnder.selector);
        vat.frob(gilk, self, int(-1), 0);

        // gems are taken from user when joining, and rico given to user
        vat.frob(gilk, self, int(stack), int(stack / 2));
        uint self_gold_bal1 = gold.balanceOf(self);
        uint self_rico_bal1 = rico.balanceOf(self);
        assertEq(self_gold_bal1 + stack, self_gold_bal0);
        assertEq(self_rico_bal1, self_rico_bal0 + stack / 2);

        // close, even without drip need 1 extra rico as rounding is in systems favour
        rico.mint(self, 1);
        vat.frob(gilk, self, -int(stack), -int(stack / 2));
        uint self_gold_bal2 = gold.balanceOf(self);
        uint self_rico_bal2 = rico.balanceOf(self);
        assertEq(self_gold_bal0, self_gold_bal2);
        assertEq(self_rico_bal0, self_rico_bal2);
    }

    function test_simple_rico_flash_mint() public {
        uint initial_rico_supply = rico.totalSupply();

        bytes memory data = abi.encodeWithSelector(chap.nop.selector);
        gems.push(arico);
        wads.push(stack);
        vat.flash(gems, wads, achap, data);

        assertEq(rico.totalSupply(), initial_rico_supply);
        assertEq(rico.balanceOf(self), 0);
        assertEq(rico.balanceOf(avat), 0);
    }

    function test_rico_reentry() public {
        bytes memory data = abi.encodeWithSelector(chap.reenter.selector, arico, flash_size * WAD);
        gems.push(arico);
        wads.push(stack);
        vm.expectRevert(Lock.ErrLock.selector);
        vat.flash(gems, wads, achap, data);
    }

    function test_revert_rico_exceed_max() public {
        bytes memory data = abi.encodeWithSelector(chap.nop.selector);
        gems.push(arico);
        wads.push(2 ** 200);
        vm.expectRevert(Vat.ErrMintCeil.selector);
        vat.flash(gems, wads, achap, data);
    }

    function test_repeat_rico_ceil() public {
        bytes memory data = abi.encodeWithSelector(chap.nop.selector);
        // borrowing max amount of rico should succeed
        gems.push(arico);
        wads.push(vat.MINT());
        vat.flash(gems, wads, achap, data);

        // borrow max amount of rico, and then repeating rico in gems should fail
        gems.push(arico);
        wads.push(1);
        vm.expectRevert(Vat.ErrMintCeil.selector);
        vat.flash(gems, wads, achap, data);
    }

    function test_multi_borrow() public {
        vat.frob(gilk, address(this), int(stack), 0);

        uint flash_gold1 = gold.balanceOf(achap);
        uint flash_rico1 = rico.balanceOf(achap);
        uint vat_gold1  = gold.balanceOf(avat);
        uint vat_rico1  = rico.balanceOf(avat);

        bytes memory data = abi.encodeWithSelector(chap.multi_borrow.selector, arico, 2 ** 100, agold, stack);
        gems.push(arico);
        wads.push(2 ** 100);
        gems.push(agold);
        wads.push(stack);
        vat.flash(gems, wads, achap, data);

        assertEq(flash_gold1, gold.balanceOf(achap));
        assertEq(flash_rico1, rico.balanceOf(achap));
        assertEq(vat_gold1,  gold.balanceOf(avat));
        assertEq(vat_rico1,  rico.balanceOf(avat));
    }

    function test_rico_flash_over_max_supply_reverts() public {
        rico.mint(self, type(uint256).max - stack);
        bytes memory data = abi.encodeWithSelector(chap.nop.selector);
        gems.push(arico);
        wads.push(2 * stack);
        vm.expectRevert(rico.ErrOverflow.selector);
        vat.flash(gems, wads, achap, data);
    }

    function test_repayment_failure() public {
        // remove any initial balance from chap
        uint chap_gold = gold.balanceOf(achap);
        uint chap_rico = rico.balanceOf(achap);
        chap.approve_sender(agold, chap_gold);
        chap.approve_sender(arico, chap_rico);
        gold.transferFrom(achap, self, chap_gold);
        rico.transferFrom(achap, self, chap_rico);

        // add rico then gold and ensure they both fail if welching
        gems.push(arico);
        wads.push(stack);
        gems.push(agold);
        wads.push(init_join * WAD);
        bytes memory data0 = abi.encodeWithSelector(chap.welch.selector, gems, wads, 0);
        bytes memory data1 = abi.encodeWithSelector(chap.welch.selector, gems, wads, 1);
        bytes memory data2 = abi.encodeWithSelector(chap.welch.selector, gems, wads, 2);
        vm.expectRevert(Gem.ErrUnderflow.selector);
        vat.flash(gems, wads, achap, data0);
        vm.expectRevert(Gem.ErrUnderflow.selector);
        vat.flash(gems, wads, achap, data1);
        // neither welching should pass
        vat.flash(gems, wads, achap, data2);

        // and in reverse gem order
        gems.pop(); gems.pop(); wads.pop(); wads.pop();
        gems.push(agold);
        wads.push(init_join * WAD);
        gems.push(arico);
        wads.push(stack);
        data0 = abi.encodeWithSelector(chap.welch.selector, gems, wads, 0);
        data1 = abi.encodeWithSelector(chap.welch.selector, gems, wads, 1);
        vm.expectRevert(Gem.ErrUnderflow.selector);
        vat.flash(gems, wads, achap, data0);
        vm.expectRevert(Gem.ErrUnderflow.selector);
        vat.flash(gems, wads, achap, data1);
    }

    function test_revert_wrong_joy() public {
        bytes memory data = abi.encodeWithSelector(chap.nop.selector);
        gems.push(arisk);
        wads.push(stack);
        vm.expectRevert(risk.ErrWard.selector);
        vat.flash(gems, wads, achap, data);
    }

    function test_handler_error() public {
        bytes memory data = abi.encodeWithSelector(chap.failure.selector);
        gems.push(arico);
        wads.push(stack);
        vm.expectRevert(bytes4(keccak256(bytes('ErrBroken()'))));
        vat.flash(gems, wads, achap, data);
    }

    function test_rico_wind_up_and_release() public {
        uint lock = 300 * WAD;
        uint draw = 200 * WAD;

        uint flash_gold1 = gold.balanceOf(achap);
        uint flash_rico1 = rico.balanceOf(achap);
        uint vat_gold1  = gold.balanceOf(avat);
        uint vat_rico1  = rico.balanceOf(avat);

        bytes memory data = abi.encodeWithSelector(chap.rico_lever.selector, agold, lock, draw);
        gems.push(arico);
        wads.push(2 ** 100);
        vat.flash(gems, wads, achap, data);

        (uint ink, uint art) = vat.urns(gilk, achap);
        assertEq(ink, lock);
        assertEq(art, draw);

        data = abi.encodeWithSelector(chap.rico_release.selector, agold, lock, draw);
        vat.flash(gems, wads, achap, data);

        assertEq(flash_gold1, gold.balanceOf(achap));
        assertEq(flash_rico1, rico.balanceOf(achap) + 1);
        assertEq(vat_gold1,  gold.balanceOf(avat));
        assertEq(vat_rico1,  rico.balanceOf(avat));
    }

    function test_gem_simple_flash() public {
        uint chap_gold1 = gold.balanceOf(achap);
        uint vat_gold1 = gold.balanceOf(avat);

        bytes memory data = abi.encodeWithSelector(chap.approve_vat.selector, agold, flash_size * WAD);
        gems.push(agold);
        wads.push(flash_size * WAD);
        vat.flash(gems, wads, achap, data);

        assertEq(gold.balanceOf(achap), chap_gold1);
        assertEq(gold.balanceOf(avat), vat_gold1);
    }

    function test_gem_flash_insufficient_approval() public {
        bytes memory data = abi.encodeWithSelector(chap.approve_vat.selector, agold, flash_size * WAD - 1);
        gems.push(agold);
        wads.push(flash_size * WAD);
        vm.expectRevert(Gem.ErrUnderflow.selector);
        vat.flash(gems, wads, achap, data);
    }

    function test_gem_flash_insufficient_assets() public {
        bytes memory data = abi.encodeWithSelector(chap.approve_vat.selector, agold, type(uint256).max);
        gems.push(agold);
        wads.push(init_join * WAD);
        vat.flash(gems, wads, achap, data);
        wads.pop();
        wads.push(init_join * WAD + 1);
        vm.expectRevert(Gem.ErrUnderflow.selector);
        vat.flash(gems, wads, achap, data);
    }

    function test_gem_flash_unsupported_gem() public {
        bytes memory data = abi.encodeWithSelector(chap.approve_vat.selector, agold, type(uint256).max);
        gems.push(agold);
        wads.push(init_join * WAD);
        vat.flash(gems, wads, achap, data);
        vat.list(agold, false);
        vm.expectRevert(gold.ErrWard.selector);
        vat.flash(gems, wads, achap, data);
    }

    function test_gem_flasher_failure() public {
        bytes memory data = abi.encodeWithSelector(chap.failure.selector);
        gems.push(agold);
        wads.push(init_join * WAD);
        vm.expectRevert(bytes4(keccak256(bytes('ErrBroken()'))));
        vat.flash(gems, wads, achap, data);
    }

    function test_gem_flash_reentry() public {
        bytes memory data = abi.encodeWithSelector(chap.reenter.selector, agold, flash_size * WAD);
        gems.push(agold);
        wads.push(init_join * WAD);
        vm.expectRevert(Lock.ErrLock.selector);
        vat.flash(gems, wads, achap, data);
    }

    function test_gem_jump_wind_up_and_release() public {
        uint lock = 1000 * WAD;
        uint draw = 500 * WAD;
        uint chap_gold1 = gold.balanceOf(achap);
        uint chap_rico1 = rico.balanceOf(achap);
        uint vat_gold1 = gold.balanceOf(avat);
        uint vat_rico1 = rico.balanceOf(avat);

        // chap had 500 gold, double it with 500 loan repaid by buying with borrowed rico
        bytes memory data = abi.encodeWithSelector(chap.gem_lever.selector, agold, lock, draw);
        gems.push(agold);
        wads.push(draw);
        vat.flash(gems, wads, achap, data);
        (uint ink, uint art) = vat.urns(gilk, achap);
        assertEq(ink, lock);
        assertEq(art, draw);

        data = abi.encodeWithSelector(chap.gem_release.selector, agold, lock, draw);
        vat.flash(gems, wads, achap, data);
        assertEq(gold.balanceOf(achap), chap_gold1);
        assertEq(rico.balanceOf(achap) + 1, chap_rico1);
        assertEq(gold.balanceOf(avat), vat_gold1);
        assertEq(rico.balanceOf(avat), vat_rico1);
    }

    function test_init_conditions() public {
        assertEq(vat.wards(self), true);
    }

    function test_rejects_unsafe_frob() public {
        (uint ink, uint art) = vat.urns(gilk, self);
        assertEq(ink, 0);
        assertEq(art, 0);
        vm.expectRevert(Vat.ErrNotSafe.selector);
        vat.frob(gilk, self, 0, int(WAD));
    }

    function owed() internal returns (uint) {
        vat.drip(gilk);
        (,uint rack,,,,,,,,,,) = vat.ilks(gilk);
        (,uint art) = vat.urns(gilk, self);
        return rack * art;
    }

    function test_drip() public {
        vat.filk(gilk, 'fee', RAY + RAY / 50);

        skip(1);
        vat.drip(gilk);
        vat.frob(gilk, self, int(100 * WAD), int(50 * WAD));

        skip(1);
        uint debt0 = owed();

        skip(1);
        uint debt1 = owed();
        assertEq(debt1, debt0 + debt0 / 50);
    }

    function test_feed_plot_safe() public {
        Vat.Spot safe0 = vat.safe(gilk, self);
        assertEq(uint(safe0), uint(Vat.Spot.Safe));

        vat.frob(gilk, self, int(100 * WAD), int(50 * WAD));

        Vat.Spot safe1 = vat.safe(gilk, self);
        assertEq(uint(safe1), uint(Vat.Spot.Safe));


        (uint ink, uint art) = vat.urns(gilk, self);
        assertEq(ink, 100 * WAD);
        assertEq(art, 50 * WAD);

        feed.push(gtag, bytes32(RAY), block.timestamp + 1000);

        Vat.Spot safe2 = vat.safe(gilk, self);
        assertEq(uint(safe2), uint(Vat.Spot.Safe));

        feed.push(gtag, bytes32(RAY / 50), block.timestamp + 1000);

        Vat.Spot safe3 = vat.safe(gilk, self);
        assertEq(uint(safe3), uint(Vat.Spot.Sunk));
    }
}
