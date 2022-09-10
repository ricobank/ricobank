// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import "forge-std/Test.sol";

import { Ball } from '../src/ball.sol';
import { GemLike } from '../src/abi.sol';
import { Flasher } from "./Flasher.sol";
import { RicoSetUp } from "./RicoHelper.sol";

contract DockTest is Test, RicoSetUp {
    uint256 public init_join = 1000;
    uint public constant flash_size = 100;
    Flasher public chap;
    address public achap;
    uint stack = WAD * 10;

    function setUp() public {
        make_bank();
        init_gold();
        dock.join_gem(avat, gilk, self, init_join * WAD);
        chap = new Flasher(adock, avat, arico, gilk);
        achap = address(chap);
        gold.mint(achap, 500 * WAD);
        gold.approve(achap, type(uint256).max);
        rico.approve(achap, type(uint256).max);
        gold.ward(achap, true);
        rico.ward(achap, true);
    }

    function test_rico_join_exit() public {
        vat.frob(gilk, address(this), int(100 * WAD), int(stack));

        vm.expectRevert(stdError.arithmeticError);
        dock.exit_rico(avat, arico, self, stack + WAD);
        dock.exit_rico(avat, arico, self, stack);
        vm.expectRevert(stdError.arithmeticError);
        dock.exit_rico(avat, arico, self, WAD);

        assertEq(rico.balanceOf(self), stack);

        vm.expectRevert(stdError.arithmeticError);
        dock.join_rico(avat, arico, self, stack + WAD);
        dock.join_rico(avat, arico, self, stack);
        vm.expectRevert(stdError.arithmeticError);
        dock.join_rico(avat, arico, self, WAD);

        assertEq(rico.balanceOf(self), 0);
    }

    function test_simple_rico_flash_mint() public {
        uint initial_rico_supply = rico.totalSupply();

        bytes memory data = abi.encodeWithSelector(chap.nop.selector);
        dock.flash(arico, stack, achap, data);

        assertEq(rico.totalSupply(), initial_rico_supply);
        assertEq(rico.balanceOf(self), 0);
        assertEq(rico.balanceOf(adock), 0);
    }

    function test_rico_reentry() public {
        bytes memory data = abi.encodeWithSelector(chap.reenter.selector, arico, flash_size * WAD);
        vm.expectRevert(dock.ErrLock.selector);
        dock.flash(arico, stack, achap, data);
    }

    function test_revert_rico_exceed_max() public {
        bytes memory data = abi.encodeWithSelector(chap.nop.selector);
        vm.expectRevert(dock.ErrMintCeil.selector);
        dock.flash(arico, 2**200, achap, data);
    }

    function test_rico_flash_over_max_supply_reverts() public {
        rico.mint(self, type(uint256).max - stack);
        bytes memory data = abi.encodeWithSelector(chap.nop.selector);
        vm.expectRevert(rico.ErrOverflow.selector);
        dock.flash(arico, 2 * stack, achap, data);
    }

    function test_revert_on_rico_repayment_failure() public {
        bytes memory data = abi.encodeWithSelector(chap.welch.selector, arico, stack);
        vm.expectRevert(rico.ErrUnderflow.selector);
        dock.flash(arico, stack, achap, data);
    }

    function test_revert_wrong_joy() public {
        bytes memory data = abi.encodeWithSelector(chap.nop.selector);
        vm.expectRevert(risk.ErrWard.selector);
        dock.flash(address(risk), stack, achap, data);
    }

    function test_handler_error() public {
        bytes memory data = abi.encodeWithSelector(chap.failure.selector, arico, stack);
        vm.expectRevert(bytes4(keccak256(bytes('ErrBroken()'))));
        dock.flash(arico, stack, achap, data);
    }

    function test_rico_wind_up_and_release() public {
        uint lock = 300 * WAD;
        uint draw = 200 * WAD;

        uint flash_gold1 = gold.balanceOf(achap);
        uint flash_rico1 = rico.balanceOf(achap);
        uint dock_gold1  = gold.balanceOf(adock);
        uint dock_rico1  = rico.balanceOf(adock);

        bytes memory data = abi.encodeWithSelector(chap.rico_lever.selector, agold, lock, draw);
        dock.flash(arico, 2**100, achap, data);

        (uint ink, uint art) = vat.urns(gilk, achap);
        assertEq(ink, lock);
        assertEq(art, draw);

        data = abi.encodeWithSelector(chap.rico_release.selector, agold, lock, draw);
        dock.flash(arico, 2**100, achap, data);

        assertEq(flash_gold1, gold.balanceOf(achap));
        assertEq(flash_rico1, rico.balanceOf(achap));
        assertEq(dock_gold1,  gold.balanceOf(adock));
        assertEq(dock_rico1,  rico.balanceOf(adock));
    }

    function test_gem_join_exit() public {
        uint exit_size = 100;
        uint vat_gem1  = vat.gem(gilk, self);
        uint own_gold1 = gold.balanceOf(self);
        assertEq(vat_gem1, init_join * WAD);
        assertEq(own_gold1, init_mint * WAD - init_join * WAD);

        dock.exit_gem(avat, gilk, self, exit_size * WAD);

        uint vat_gem2  = vat.gem(gilk, self);
        uint own_gold2 = gold.balanceOf(self);
        assertEq(vat_gem2, init_join * WAD - exit_size * WAD);
        assertEq(own_gold2, init_mint * WAD - init_join * WAD + exit_size * WAD);

        vm.expectRevert("ERR_MATH_UIADD_NEG");
        dock.exit_gem(avat, gilk, self, init_join * WAD - exit_size * WAD + 1);
    }

    function test_gem_simple_flash() public {
        uint chap_gold1 = gold.balanceOf(achap);
        uint dock_gold1 = gold.balanceOf(adock);

        bytes memory data = abi.encodeWithSelector(chap.approve_dock.selector, agold, flash_size * WAD);
        dock.flash(agold, flash_size * WAD, achap, data);

        assertEq(gold.balanceOf(achap), chap_gold1);
        assertEq(gold.balanceOf(adock), dock_gold1);
    }

    function test_gem_flash_insufficient_approval() public {
        bytes memory data = abi.encodeWithSelector(chap.approve_dock.selector, agold, flash_size * WAD - 1);
        vm.expectRevert(gold.ErrUnderflow.selector);
        dock.flash(agold, flash_size * WAD, achap, data);
    }

    function test_gem_flash_insufficient_assets() public {
        bytes memory data = abi.encodeWithSelector(chap.approve_dock.selector, agold, type(uint256).max);
        dock.flash(agold, init_join * WAD, achap, data);
        vm.expectRevert(gold.ErrUnderflow.selector);
        dock.flash(agold, init_join * WAD + 1, achap, data);
    }

    function test_gem_flash_unsupported_gem() public {
        bytes memory data = abi.encodeWithSelector(chap.approve_dock.selector, agold, type(uint256).max);
        dock.flash(agold, init_join * WAD, achap, data);
        dock.list(agold, false);
        vm.expectRevert(gold.ErrWard.selector);
        dock.flash(agold, init_join * WAD, achap, data);
    }

    function test_gem_flash_repayment_failure() public {
        bytes memory data = abi.encodeWithSelector(chap.welch.selector, agold, flash_size * WAD);
        vm.expectRevert(gold.ErrUnderflow.selector);
        dock.flash(agold, init_join * WAD, achap, data);
    }

    function test_gem_flasher_failure() public {
        bytes memory data = abi.encodeWithSelector(chap.failure.selector, agold, flash_size * WAD);
        vm.expectRevert(bytes4(keccak256(bytes('ErrBroken()'))));
        dock.flash(agold, init_join * WAD, achap, data);
    }

    function test_gem_flash_reentry() public {
        bytes memory data = abi.encodeWithSelector(chap.reenter.selector, agold, flash_size * WAD);
        vm.expectRevert(dock.ErrLock.selector);
        dock.flash(agold, init_join * WAD, achap, data);
    }

    function test_gem_jump_wind_up_and_release() public {
        uint lock = 1000 * WAD;
        uint draw = 500 * WAD;
        uint chap_gold1 = gold.balanceOf(achap);
        uint chap_rico1 = rico.balanceOf(achap);
        uint dock_gold1 = gold.balanceOf(adock);
        uint dock_rico1 = rico.balanceOf(adock);

        // chap had 500 gold, double it with 500 loan repaid by buying with borrowed rico
        bytes memory data = abi.encodeWithSelector(chap.gem_lever.selector, agold, lock, draw);
        dock.flash(agold, draw, achap, data);

        (uint ink, uint art) = vat.urns(gilk, achap);
        assertEq(ink, lock);
        assertEq(art, draw);

        data = abi.encodeWithSelector(chap.gem_release.selector, agold, lock, draw);
        dock.flash(agold, draw, achap, data);
        assertEq(gold.balanceOf(achap), chap_gold1);
        assertEq(rico.balanceOf(achap), chap_rico1);
        assertEq(gold.balanceOf(adock), dock_gold1);
        assertEq(rico.balanceOf(adock), dock_rico1);
    }
}
