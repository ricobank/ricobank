// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import "forge-std/Test.sol";

import { Ball } from '../src/ball.sol';
import { GemLike } from '../src/abi.sol';
import { RicoSetUp } from "./RicoHelper.sol";
import { VatLike } from '../src/abi.sol';

contract VatTest is Test, RicoSetUp {
    uint256 public init_join = 1000;
    uint stack = WAD * 10;
    bytes32[] ilks;

    function setUp() public {
        make_bank();
        init_gold();
        ilks.push(gilk);
        rico.approve(address(flow), type(uint256).max);
        dock.join_gem(avat, gilk, self, init_join * WAD);
        vat.filk(gilk, 'duty', 1000000001546067052200000000);  // 5%
    }

    /* urn safety tests */

    // goldusd, par, and liqr all = 1 after set up
    function test_create_unsafe() public {
        // art should not exceed ink
        vm.expectRevert("Vat/not-safe");
        vat.frob(gilk, address(this), int(stack), int(stack) + 1);

        // art should not increase if iffy
        skip(1100);
        vm.expectRevert("Vat/not-safe");
        vat.frob(gilk, address(this), int(stack), int(1));
    }

    function test_rack_puts_urn_underwater() public {
        // frob to exact edge
        vat.frob(gilk, address(this), int(stack), int(stack));
        assertTrue(vat.safe(gilk, self) == VatLike.Spot.Safe);

        // accrue some interest to sink
        skip(100);
        vat.drip(gilk);
        assertTrue(vat.safe(gilk, self) == VatLike.Spot.Sunk);

        // neg quantity rate should refloat
        vat.filk(gilk, 'duty', RAY / 2);
        skip(100);
        vat.drip(gilk);
        assertTrue(vat.safe(gilk, self) == VatLike.Spot.Safe);
    }

    function test_liqr_puts_urn_underwater() public {
        vat.frob(gilk, address(this), int(stack), int(stack));
        assertTrue(vat.safe(gilk, self) == VatLike.Spot.Safe);
        vat.filk(gilk, 'liqr', RAY - 1000000);
        assertTrue(vat.safe(gilk, self) == VatLike.Spot.Sunk);

        vat.filk(gilk, 'liqr', RAY + 1000000);
        assertTrue(vat.safe(gilk, self) == VatLike.Spot.Safe);
    }

    function test_gold_crash_sinks_urn() public {
        vat.frob(gilk, address(this), int(stack), int(stack));
        assertTrue(vat.safe(gilk, self) == VatLike.Spot.Safe);

        feed.push(gtag, bytes32(RAY / 2), block.timestamp + 1000);
        assertTrue(vat.safe(gilk, self) == VatLike.Spot.Sunk);

        feed.push(gtag, bytes32(RAY * 2), block.timestamp + 1000);
        assertTrue(vat.safe(gilk, self) == VatLike.Spot.Safe);
    }

    function test_time_makes_urn_iffy() public {
        vat.frob(gilk, address(this), int(stack), int(stack));
        assertTrue(vat.safe(gilk, self) == VatLike.Spot.Safe);

        // feed was set will ttl of now + 1000
        skip(1100);
        assertTrue(vat.safe(gilk, self) == VatLike.Spot.Iffy);

        // without a drip an update should refloat urn
        feed.push(gtag, bytes32(RAY), block.timestamp + 1000);
        assertTrue(vat.safe(gilk, self) == VatLike.Spot.Safe);
    }

    function test_frob_refloat() public {
        vat.frob(gilk, address(this), int(stack), int(stack));
        assertTrue(vat.safe(gilk, self) == VatLike.Spot.Safe);

        feed.push(gtag, bytes32(RAY / 2), block.timestamp + 1000);
        assertTrue(vat.safe(gilk, self) == VatLike.Spot.Sunk);

        vat.frob(gilk, address(this), int(stack), int(0));
        assertTrue(vat.safe(gilk, self) == VatLike.Spot.Safe);
    }

    function test_increasing_risk_sunk_urn() public {
        vat.frob(gilk, address(this), int(stack), int(stack));
        assertTrue(vat.safe(gilk, self) == VatLike.Spot.Safe);

        feed.push(gtag, bytes32(RAY / 2), block.timestamp + 1000);
        assertTrue(vat.safe(gilk, self) == VatLike.Spot.Sunk);

        //should always be able to decrease art
        vat.frob(gilk, address(this), int(0), int(-1));
        //should always be able to increase ink
        vat.frob(gilk, address(this), int(1), int(0));

        // should not be able to increase art of sunk urn
        vm.expectRevert("Vat/not-safe");
        vat.frob(gilk, address(this), int(10), int(1));

        // should not be able to decrease ink of sunk urn
        vm.expectRevert("Vat/not-safe");
        vat.frob(gilk, address(this), int(-1), int(1));
    }

    function test_increasing_risk_iffy_urn() public {
        vat.frob(gilk, address(this), int(stack), int(10));
        assertTrue(vat.safe(gilk, self) == VatLike.Spot.Safe);

        skip(1100);
        assertTrue(vat.safe(gilk, self) == VatLike.Spot.Iffy);

        //should always be able to decrease art
        vat.frob(gilk, address(this), int(0), int(-1));
        //should always be able to increase ink
        vat.frob(gilk, address(this), int(1), int(0));

        // should not be able to increase art of iffy urn
        vm.expectRevert("Vat/not-safe");
        vat.frob(gilk, address(this), int(10), int(1));

        // should not be able to decrease ink of iffy urn
        vm.expectRevert("Vat/not-safe");
        vat.frob(gilk, address(this), int(-1), int(1));
    }

    function test_increasing_risk_safe_urn() public {
        vat.frob(gilk, address(this), int(stack), int(10));
        assertTrue(vat.safe(gilk, self) == VatLike.Spot.Safe);

        //should always be able to decrease art
        vat.frob(gilk, address(this), int(0), int(-1));
        //should always be able to increase ink
        vat.frob(gilk, address(this), int(1), int(0));

        // should be able to increase art of iffy urn
        vat.frob(gilk, address(this), int(0), int(1));

        // should be able to decrease ink of iffy urn
        vat.frob(gilk, address(this), int(-1), int(0));
    }
}


contract VatJsTest is VatTest {
    address me;
    address ali;
    bytes32 i0;

    modifier _js_ {
        me = address(this);
        ali = me;
        i0 = ilks[0];
        _;
    }

    function test_init_conditions() public _js_ {
        assertEq(vat.wards(ali), true);
    }

    function test_gem_join() public _js_ {
        assertEq(vat.gem(i0, ali), 1000 * WAD);
        assertEq(GemLike(WETH).balanceOf(ali), 0);
    }

    function test_frob() public _js_ {
        vat.frob(i0, ali, int(6 * WAD), 0);

        (uint ink, uint art) = vat.urns(i0, ali);
        assertEq(ink, 6 * WAD);
        assertEq(vat.gem(i0, ali), 994 * WAD);

        vat.frob(i0, ali, -int(6 * WAD), 0);
        assertEq(vat.gem(i0, ali), 1000 * WAD);
    }

    function test_rejects_unsafe_frob() public _js_ {
        (uint ink, uint art) = vat.urns(i0, ali);
        assertEq(ink, 0);
        assertEq(art, 0);
        vm.expectRevert("Vat/not-safe");
        vat.frob(i0, ali, 0, int(WAD));
    }

    function owed() internal returns (uint) {
        vat.drip(i0);
        VatLike.Ilk memory ilk = vat.ilks(i0);
        (uint ink, uint art) = vat.urns(i0, ali);
        return ilk.rack * art;
    }

    function test_drip() public _js_ {
        vat.filk(i0, 'duty', RAY + RAY / 50);

        skip(1);
        vat.drip(i0);
        vat.frob(i0, ali, int(100 * WAD), int(50 * WAD));

        skip(1);
        uint debt0 = owed();

        skip(1);
        uint debt1 = owed();
        assertEq(debt1, debt0 + debt0 / 50);
    }

    function test_feed_plot_safe() public _js_ {
        VatLike.Spot safe0 = vat.safe(i0, ali);
        assertEq(uint(safe0), uint(VatLike.Spot.Safe));

        vat.frob(i0, ali, int(100 * WAD), int(50 * WAD));

        VatLike.Spot safe1 = vat.safe(i0, ali);
        assertEq(uint(safe1), uint(VatLike.Spot.Safe));


        (uint ink, uint art) = vat.urns(i0, ali);
        assertEq(ink, 100 * WAD);
        assertEq(art, 50 * WAD);

        feed.push(gtag, bytes32(RAY), block.timestamp + 1000);

        VatLike.Spot safe2 = vat.safe(i0, ali);
        assertEq(uint(safe2), uint(VatLike.Spot.Safe));

        feed.push(gtag, bytes32(RAY / 50), block.timestamp + 1000);

        VatLike.Spot safe3 = vat.safe(i0, ali);
        assertEq(uint(safe3), uint(VatLike.Spot.Sunk));
    }
}