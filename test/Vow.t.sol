// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import { Gem } from '../lib/gemfab/src/gem.sol';
import { Ward } from '../lib/feedbase/src/mixin/ward.sol';
import { Ball } from '../src/ball.sol';
import { Vat } from '../src/vat.sol';
import { Vow } from '../src/vow.sol';
import { RicoSetUp, WethLike, Guy } from "./RicoHelper.sol";
import { Asset, PoolArgs } from "./UniHelper.sol";
import { DutchFlower } from '../src/flow.sol';
import { Math } from '../src/mixin/math.sol';
import { ERC20Hook } from '../src/hook/ERC20hook.sol';

// integrated vow/flow tests
contract VowTest is Test, RicoSetUp {
    uint256 public init_join = 1000;
    uint stack = WAD * 10;
    bytes32[] ilks;
    address rico_risk_pool;
    uint back_count;

    function setUp() public {
        make_bank();
        init_gold();
        ilks.push(gilk);
        rico.approve(address(flow), type(uint256).max);

        hook.pair(agold, 'fel', FEL);
        vow.pair(arico, 'fel', FEL);
        vow.pair(arisk, 'fel', FEL);
        vow.file('vel', 1e18);
        vow.file('rel', 1e12);
        vow.file('bel', 0);
        vow.file('cel', 600);

        // have 10k each of rico, risk and gold
        gold.approve(router, type(uint256).max);
        rico.approve(router, type(uint256).max);
        risk.approve(router, type(uint256).max);
        gold.approve(address(flow), type(uint256).max);
        rico.approve(address(flow), type(uint256).max);
        risk.approve(address(flow), type(uint256).max);

        rico_risk_pool = getPoolAddr(arico, arisk, 3000);
        rico_mint(2000 * WAD, true);
        risk.mint(self, 1000 * WAD);
        PoolArgs memory rico_risk_args = getArgs(arico, 1000 * WAD, arisk, 1000 * WAD, 3000, x96(1));
        join_pool(rico_risk_args);

        PoolArgs memory gold_rico_args = getArgs(agold, 1000 * WAD, arico, 1000 * WAD, 3000, x96(1));
        create_and_join_pool(gold_rico_args);

        guy = new Guy(vat, flow);
    }

    function test_keep_deficit_gas() public {
        feedpush(grtag, bytes32(1000 * RAY), block.timestamp + 1000);
        vat.frob(gilk, self, int(WAD), int(WAD));
        feedpush(grtag, bytes32(0), block.timestamp + 1000);
        vow.bail(gilk, self);

        bytes32[] memory gilks = new bytes32[](2);
        gilks[0] = gilk;
        gilks[1] = gilk;
        uint gas = gasleft();
        uint aid = vow.keep(gilks);
        check_gas(gas, 355219);
        assertGt(aid, 0);
    }

    function test_keep_surplus_gas() public {
        vat.filk(gilk, 'fee', 2 * RAY);
        feedpush(grtag, bytes32(1000 * RAY), block.timestamp + 1000);
        vat.frob(gilk, self, int(WAD), int(WAD));
        skip(1);

        bytes32[] memory gilks = new bytes32[](2);
        gilks[0] = gilk;
        gilks[1] = gilk;
        uint gas = gasleft();
        uint aid = vow.keep(gilks);
        check_gas(gas, 418432);
        assertGt(aid, 0);
    }

    function test_flowback_gas() public {
        feedpush(grtag, bytes32(1000 * RAY), block.timestamp + 1000);
        vat.frob(gilk, self, int(WAD), int(WAD));
        feedpush(grtag, bytes32(0), block.timestamp + 1000);

        uint aid = vow.bail(gilk, self);
        gold.mint(avow, WAD);
        uint gas = gasleft();
        hook.flowback(aid, WAD);
        check_gas(gas, 46293);
    }

    function test_bail_gas() public {
        feedpush(grtag, bytes32(1000 * RAY), block.timestamp + 1000);
        vat.frob(gilk, self, int(WAD), int(WAD));
        feedpush(grtag, bytes32(0), block.timestamp + 1000);
        uint gas = gasleft();
        vow.bail(gilk, self);
        check_gas(gas, 337783);
    }

    // goldusd, par, and liqr all = 1 after setup
    function test_risk_ramp_is_used() public {
        feedpush(grtag, bytes32(RAY * 1000), block.timestamp + 1000);
        vat.frob(gilk, address(this), int(init_join * WAD), int(stack) * 1000);
 
        // set rate of risk sales to near zero
        // set mint ramp higher to use risk ramp
        vow.file('vel', WAD);
        vow.file('rel', WAD);
        vow.file('bel', block.timestamp - 1);
        vow.file('cel', 1);
        hook.pair(agold, 'fel', RAY / 10);

        vow.pair(arisk, 'fel', RAY / 10);

        // setup frobbed to edge, dropping gold price puts system way underwater
        feedpush(grtag, bytes32(RAY), block.timestamp + 10000);

        // create the sin and kick off risk sale
        uint supply = risk.totalSupply();
        vm.expectCall(avat, abi.encodeWithSelector(
            Vat.grab.selector, gilk, self, self
        ));
        uint baid = vow.bail(gilk, self);
        vm.expectCall(aflow, abi.encodeWithSelector(
            DutchFlower.flow.selector, avow, arisk, WAD, arico, type(uint).max, self
        ));
        uint kaid = vow.keep(ilks);
        assertEq(risk.totalSupply(), supply + WAD);
        assertFalse(baid == kaid);

        rico_mint(10000 * WAD, true);
        rico.transfer(address(guy), 10000 * WAD);
        guy.approve(arico, aflow, UINT256_MAX);

        // start at ~10000 * RAY...need to go down to 100 * RAY
        // so that 1/10 of the ink covers the debt at that price
        feedpush(grtag, bytes32(10000 * RAY), block.timestamp + 1000);
        skip(2);
        uint hookgold = gold.balanceOf(ahook);
        guy.glug{value: rmul(block.basefee, GEL)}(baid);
        // 100 ink spent
        assertEq(gold.balanceOf(ahook), hookgold - WAD * 100);

        rico_mint(10000 * WAD, true);
        rico.transfer(address(guy), 10000 * WAD);
        feedpush(RISK_RICO_TAG, bytes32(10000 * RAY), block.timestamp + 1000);
        uint guyrico = rico.balanceOf(address(guy));
        uint vowrisk = risk.balanceOf(avow);
        guy.glug{value: rmul(block.basefee, GEL)}(kaid);

        // vow flow.flow'd for max possible - should receive nothing back
        assertEq(risk.balanceOf(avow), vowrisk);

        (uint makers, uint takers) = flow.clip(
            WAD, UINT256_MAX, grow(10 ** 50, RAY / 10, 21)
        );
        assertEq(rico.balanceOf(address(guy)), guyrico - makers);
        assertEq(risk.balanceOf(address(guy)), takers);
    }

    function test_wards() public {
        hook.flowback(0, 0);
        vow.file('vel', WAD);
        vow.link('flow', address(flow));
        vow.pair(arisk, 'fel', 1);

        vow.give(address(0));
        hook.give(address(0));


        vm.expectRevert();
        hook.flowback(0, 0);
        vow.grant(arico);
        vm.expectRevert(abi.encodeWithSelector(
            Ward.ErrWard.selector, self, avow, Vow.file.selector
        ));
        vow.file('vel', WAD);
        vm.expectRevert(abi.encodeWithSelector(
            Ward.ErrWard.selector, self, avow, Vow.link.selector
        ));
        vow.link('flow', address(flow));
        vm.expectRevert(abi.encodeWithSelector(
            Ward.ErrWard.selector, self, avow, Vow.pair.selector
        ));
        vow.pair(arisk, 'fel', 1);

        vow.keep(ilks);
        vat.frob(gilk, self, int(WAD), int(WAD));
        vm.expectRevert(Vow.ErrSafeBail.selector);
        vow.bail(gilk, self);
    }

    function test_flowback_1() public {
        rico_mint(WAD / 2, true);
        rico.transfer(address(guy), WAD / 2);
        guy.approve(arico, aflow, UINT256_MAX);

        hook.pair(agold, 'fel', RAY / 2);
        (uint ink, uint art) = vat.urns(gilk, self);
        feedpush(grtag, bytes32(1000000 * RAY), type(uint).max);
        vat.frob(gilk, self, int(WAD), int(WAD / 2));

        feedpush(grtag, bytes32(0), type(uint).max);
        uint aid = vow.bail(gilk, self);

        (ink,) = vat.urns(gilk, self);
        assertEq(ink, 0);

        feedpush(grtag, bytes32(4 * RAY), block.timestamp + 1000);
        skip(1);
        guy.glug{value: rmul(block.basefee, GEL)}(aid);

        (ink, art) = vat.urns(gilk, self);
        assertEq(art, 0);
        assertEq(ink, WAD * 3 / 4);

        // sale gone
        (bytes32 saleilk, address saleurn) = hook.sales(aid);
        assertEq(saleilk, bytes32(0));
        assertEq(saleurn, azero);
    }

    // can't bail 2**255, but can keep 2**255
    function test_flowback_negative_one() public {
        uint UINT_NEG_ONE = 2 ** 255;
        hook.pair(agold, 'fel', FEL);
        feedpush(grtag, bytes32(1000000 * RAY), type(uint).max);
        vat.frob(gilk, self, int(WAD), int(WAD));
        skip(BANKYEAR * 1000);
        uint aid = vow.bail(gilk, self);
        // with both mints, should end up with totalSupply
        // around UINT_NEG_ONE*3/4
        risk.mint(self, UINT_NEG_ONE / 2);
        vow.file('vel', type(uint).max);
        vow.file('rel', 3 * WAD);
        vow.file('bel', 0);
        vow.file('cel', 1);
        vow.pair(arisk, 'fel', FEL);

        // should fail to wmul(rel, totalSupply) in clip
        // making such high refunds impossible
        // todo error selector once math has proper errors
        vm.expectRevert();
        vow.keep(ilks);

        // ok but flowback from here instead...
        // todo vat test to show UINT_NEG_ONE ink impossible
        vm.expectRevert(ERC20Hook.ErrBigFlowback.selector);
        hook.flowback(aid, 2 ** 255);
        // should fail from rad conversion in safe
        // todo error selector once math has proper errors
        vm.expectRevert();
        hook.flowback(aid, 2 ** 255 - 1);
    }

    uint depth_rf;
    bytes32 lastilk_rf;
    address lasturn_rf;
    uint aid_rf;
    function frob(bytes32 ilk, address urn,int,int) external {
        lastilk_rf = ilk;
        lasturn_rf = urn;
        if (depth_rf > 0) {
            depth_rf--;
            hook.flowback(aid_rf, 2);
        }
    }

    function test_reentrant_flowback() public {
        hook.pair(agold, 'fel', FEL);
        feedpush(grtag, bytes32(1000000 * RAY), type(uint).max);
        vat.frob(gilk, self, int(WAD), int(WAD));
        skip(BANKYEAR * 1000);
        aid_rf = vow.bail(gilk, self);
 
        // ward self
        vm.prank(address(flow));
        vow.give(self);
        vow.link('vat', self);

        // will recursively call flowback
        // second call should be on deleted sale
        depth_rf = 1;
        hook.flowback(aid_rf, 2);
        assertEq(uint(lastilk_rf), 0);
        assertEq(uint160(lasturn_rf), 0);
    }

    function test_drip() public {
        (,,,,,uint rho,,,) = vat.ilks(gilk);
        assertEq(rho, block.timestamp);
        assertEq(rico.balanceOf(self), 0);

        vat.filk(gilk, 'fee', 2 * RAY);
        feedpush(grtag, bytes32(RAY * 1000), type(uint).max);
        vat.frob(gilk, address(this), int(WAD), int(WAD));
        uint firstrico = rico.balanceOf(self);
        rico_mint(1, false); // vat burns 1 extra to round in system's favor
        vat.frob(gilk, address(this), -int(WAD), -int(WAD));

        skip(1);
        // can only mint a wad rico for a wad gold
        vat.frob(gilk, address(this), int(WAD), int(WAD));
        assertEq(rico.balanceOf(self), firstrico);
        rico_mint(1, false);
        vat.frob(gilk, address(this), -int(WAD), -int(WAD));

        // until drip, then can mint more
        vow.drip(gilk);
        assertEq(rico.balanceOf(self), 0);
        vat.frob(gilk, address(this), int(WAD), int(WAD));
        assertEq(rico.balanceOf(self), firstrico * 2);
    }

    function test_keep_balanced() public {
        vat.filk(gilk, 'fee', 2 * RAY);

        feedpush(grtag, bytes32(RAY * 1000), block.timestamp + 1000);
        uint amt = vat.sin(avow) / RAY;
        vat.frob(gilk, address(this), int(amt), int(amt));
        skip(1);

        feedpush(grtag, bytes32(0), block.timestamp + 10000);

        assertEq(rico.balanceOf(avow), 0);
        uint256 aid = vow.keep(ilks);
        assertEq(rico.balanceOf(avow), vat.sin(avow) / RAY);
        assertEq(aid, 0);
    }

    function test_keep_unbalanced_slightly_more_rico() public {
        vat.filk(gilk, 'fee', 2 * RAY);

        feedpush(grtag, bytes32(RAY * 1000), block.timestamp + 1000);
        uint amt = vat.sin(avow) / RAY + 1;
        vat.frob(gilk, address(this), int(amt), int(amt));
        skip(1);

        feedpush(grtag, bytes32(0), block.timestamp + 10000);

        assertEq(rico.balanceOf(avow), 0);
        uint256 aid = vow.keep(ilks);
        assertEq(rico.balanceOf(avow), 1);
        (
            address vow, address flo, address hag, uint ham, address wag, uint wam,
            uint gun, address gir, uint gim, uint valid
        ) = flow.auctions(aid);
        assertEq(hag, arico);
        assertEq(ham, 1);
        assertEq(vat.sin(avow), RAY);
        assertGt(aid, 0);

        assertEq(vow, avow);
        assertEq(flo, avow);
        assertEq(wag, arisk);
        assertEq(wam, type(uint).max);

        assertEq(gun, block.timestamp);
        assertEq(gir, self);
        // TODO set feed to 1000 * RAY
        assertEq(gim, rmul(GEL, block.basefee));
        assertEq(valid, uint(DutchFlower.Valid.VALID));
    }

    function test_keep_unbalanced_slightly_more_sin() public {
        vat.filk(gilk, 'fee', 2 * RAY);

        feedpush(grtag, bytes32(RAY * 1000), block.timestamp + 1000);
        uint amt = vat.sin(avow) / RAY - 1;
        vat.frob(gilk, address(this), int(amt), int(amt));
        skip(1);

        feedpush(grtag, bytes32(0), block.timestamp + 10000);

        assertEq(rico.balanceOf(avow), 0);
        (uint vel, uint rel, uint bel, uint cel) = vow.ramp();
        uint flop = min(wmul(rel, risk.totalSupply()), vel) * min(block.timestamp - bel, cel);
        uint256 aid = vow.keep(ilks);
        assertEq(rico.balanceOf(avow), 1);
        assertEq(vat.sin(avow), 2 * RAY);
        assertGt(aid, 0);

        (
            address vow, address flo, address hag, uint ham, address wag, uint wam,
            uint gun, address gir, uint gim, uint valid
        ) = flow.auctions(aid);

        assertEq(hag, arisk);
        assertEq(ham, flop);

        assertEq(vow, avow);
        assertEq(flo, avow);
        assertEq(wag, arico);
        assertEq(wam, type(uint).max);

        assertEq(gun, block.timestamp);
        assertEq(gir, address(self));
        // todo set feeds
        assertEq(gim, rmul(GEL, block.basefee));
        assertEq(valid, uint(DutchFlower.Valid.VALID));
    }

    function test_bail_hook() public {
        Hook hook = new Hook();
        vat.filk(gilk, 'hook', uint(bytes32(bytes20(address(hook)))));
        vat.frob(gilk, self, int(WAD), int(WAD));
        uint vowgoldbefore = gold.balanceOf(avow);

        ZeroHook zhook = new ZeroHook();
        vat.filk(gilk, 'hook', uint(bytes32(bytes20(address(zhook)))));
        bytes memory hookdata = abi.encodeCall(
            zhook.grabhook,
            (avow, gilk, self, WAD, WAD, WAD, self)
        );
        vm.expectCall(address(zhook), hookdata);

        uint aid = vow.bail(gilk, self);
        assertEq(gold.balanceOf(avow), vowgoldbefore);
        assertEq(aid, 0);
    }

}

contract Hook {
    function frobhook(
        address urn, bytes32 i, address u, int dink, int dart
    ) external {}
    function grabhook(
        address urn, bytes32 i, address u, uint ink, uint art, uint bill, address keeper
    ) external returns (uint) {}
    function safehook(
        bytes32, address
    ) pure external returns (bytes32, uint){return(bytes32(uint(1000 * 10 ** 27)), type(uint256).max);}
}
contract ZeroHook {
    function frobhook(
        address urn, bytes32 i, address u, int dink, int dart
    ) external {}
    function grabhook(
        address urn, bytes32 i, address u, uint ink, uint art, uint bill, address keeper
    ) external returns (uint) {}
    function safehook(
        bytes32, address
    ) pure external returns (bytes32, uint){return(bytes32(uint(0)), type(uint256).max);}
}

contract Usr {
    WethLike weth;
    Vat vat;
    constructor(Vat _vat, WethLike _weth) {
        weth = _weth;
        vat  = _vat;
    }
    function deposit() public payable {
        weth.deposit{value: msg.value}();
    }
    function approve(address usr, uint amt) public {
        weth.approve(usr, amt);
    }
    function frob(bytes32 ilk, address usr, int dink, int dart) public {
        vat.frob(ilk, usr, dink, dart);
    }
    function transfer(address gem, address dst, uint amt) public {
        Gem(gem).transfer(dst, amt);
    }
}

contract VowJsTest is Test, RicoSetUp {
    // me == js ALI
    address me;
    Usr bob;
    Usr cat;
    address b;
    address c;
    address rico_risk_pool;
    WethLike weth;
    bytes32 i0;
    bytes32[] ilks;
    uint prevcount;

    function setUp() public {
        make_bank();
        init_dai();
        init_gold();
        weth = WethLike(WETH);
        me = address(this);
        bob = new Usr(vat, weth);
        cat = new Usr(vat, weth);
        b = address(bob);
        c = address(cat);
        i0 = wilk;
        ilks.push(i0);

        weth.deposit{value: 6000 * WAD}();
        risk.mint(me, 10000 * WAD);
        weth.approve(address(hook), UINT256_MAX);

        vat.file('ceil', 10000 * RAD);
        vat.filk(i0, 'line', 10000 * RAD);
        vat.filk(i0, 'chop', RAY * 11 / 10);

        vow.pair(arisk, 'fel', FEL);
        vow.file('vel', WAD);
        vow.file('rel', WAD / 10000);
        vow.file('bel', 0);
        vow.file('cel', 60);

        feedpush(wrtag, bytes32(RAY), block.timestamp + 2 * BANKYEAR);
        feedpush(grtag, bytes32(RAY), block.timestamp + 2 * BANKYEAR);
        uint fee = 1000000001546067052200000000; // == ray(1.05 ** (1/BANKYEAR))
        vat.filk(i0, 'fee', fee);
        vat.frob(i0, me, int(100 * WAD), 0);
        vat.frob(i0, me, 0, int(99 * WAD));

        uint bal = rico.balanceOf(me);
        assertEq(bal, 99 * WAD);
        Vat.Spot safe1 = vat.safe(i0, me);
        assertEq(uint(safe1), uint(Vat.Spot.Safe));

        cat.deposit{value: 7000 * WAD}();
        cat.approve(address(hook), UINT256_MAX);
        cat.frob(i0, c, int(4001 * WAD), int(4000 * WAD));
        cat.transfer(arico, me, 4000 * WAD);

        weth.approve(address(router), UINT256_MAX);
        rico.approve(address(router), UINT256_MAX);
        risk.approve(address(router), UINT256_MAX);
        dai.approve(address(router), UINT256_MAX);

        PoolArgs memory dai_rico_args = getArgs(DAI, 2000 * WAD, arico, 2000 * WAD, 500, x96(1));
        join_pool(dai_rico_args);

        PoolArgs memory risk_rico_args = getArgs(arisk, 2000 * WAD, arico, 2000 * WAD, 3000, x96(1));
        join_pool(risk_rico_args);
        rico_risk_pool = getPoolAddr(arisk, arico, 3000);

        hook.pair(WETH, 'fel', FEL);
        vow.pair(arico, 'fel', FEL);

        prevcount = flow.count();

        vow.file('vel', 200 * WAD);
        vow.file('rel', WAD);
        vow.file('bel', block.timestamp);
        vow.file('cel', 1);
        guy = new Guy(vat, flow);

        vow.pair(arisk, 'fel', RAY / 10);
        vow.pair(arico, 'fel', RAY / 10);
        hook.pair(agold, 'fel', RAY / 10);
        hook.pair(WETH, 'fel', RAY / 10);
    }

    function test_bail_urns_1yr_unsafe() public {
        skip(BANKYEAR);
        vow.keep(ilks);

        assertEq(uint(vat.safe(i0, me)), uint(Vat.Spot.Sunk));

        uint sin0 = vat.sin(avow);
        uint gembal0 = weth.balanceOf(address(flow));
        uint vow_rico0 = rico.balanceOf(avow);
        assertEq(sin0 / RAY, 0);
        assertEq(gembal0, 0);
        assertEq(vow_rico0, 0);

        vm.expectCall(address(flow), abi.encodePacked(flow.flow.selector));
        uint256 aid = vow.bail(i0, me);
        // after bail the ink should have been grabbed
        (uint ink, uint art) = vat.urns(i0, me);
        assertEq(ink, 0);
        assertEq(art, 0);

        rico_mint(1000 * WAD, false);
        rico.transfer(address(guy), 1000 * WAD);
        guy.approve(arico, aflow, UINT256_MAX);
        feedpush(wrtag, bytes32(100000 * RAY), UINT256_MAX);
        skip(3);
        guy.glug{value: rmul(block.basefee, GEL)}(aid);
        (ink, art) = vat.urns(i0, me);
        // weth-dai market price is much higher than 1 in fork block, expect a refund
        assertGt(ink, 0);

        uint sin1 = vat.sin(avow);
        uint gembal1 = weth.balanceOf(address(flow));
        uint vow_rico1 = rico.balanceOf(avow);
        assertEq(art, 0);
        assertGt(sin1, 0);
        assertGt(vow_rico1, 0);
        assertEq(gembal1, 0);
    }

    function test_bail_urns_when_safe() public {
        vm.expectRevert(Vow.ErrSafeBail.selector);
        vow.bail(i0, me);
        assertEq(flow.count(), prevcount); // flow hasn't been called

        uint sin0 = vat.sin(avow);
        uint gembal0 = weth.balanceOf(address(flow));
        assertEq(sin0 / RAY, 0);
        assertEq(gembal0, 0);

        skip(BANKYEAR);
        vm.expectCall(address(flow), abi.encodePacked(flow.flow.selector));
        vow.bail(i0, me);
        vm.expectRevert(Vow.ErrSafeBail.selector);
        vow.bail(i0, me);
    }

    function test_keep_vow_1yr_drip_flap() public {
        uint initial_total = rico.totalSupply();
        skip(BANKYEAR);
        vm.expectCall(address(flow), abi.encodePacked(flow.flow.selector));
        vow.keep(ilks);
        uint final_total = rico.totalSupply();
        assertGt(final_total, initial_total);
        // minted 4099, fee is 1.05. 0.05*4099 as no surplus buffer
        assertGe(final_total - initial_total, 204.94e18);
        assertLe(final_total - initial_total, 204.96e18);
    }

    function test_keep_vow_1yr_drip_flop() public {
        skip(BANKYEAR);
        vm.expectCall(address(flow), abi.encodePacked(flow.flow.selector));
        vow.bail(i0, me);

        vm.expectCall(avat, abi.encodePacked(Vat.heal.selector));
        vm.expectCall(address(flow), abi.encodePacked(flow.flow.selector));
        vow.keep(ilks);
    }

    function test_keep_rate_limiting_flop_absolute_rate() public {
        vat.file('ceil', 100000 * RAD);
        vat.filk(i0, 'line', 100000 * RAD);
        vow.file('vel', WAD);
        vow.file('rel', WAD);
        vow.file('bel', block.timestamp - 1);
        vow.file('cel', 1);

        assertGt(risk.totalSupply(), WAD);
        uint risksupply = risk.totalSupply();
        prepguyrico(10000 * WAD, true);
        uint aid = vow.keep(ilks);
        assertGt(aid, 0);
        (,,address hag, uint ham, address wag, uint wam,,,,uint valid) = flow.auctions(aid);
        assertEq(hag, arisk);
        assertEq(ham, WAD);
        assertEq(wag, arico);
        assertEq(wam, UINT256_MAX);
        assertEq(risk.totalSupply(), risksupply + WAD);
        assertEq(valid, uint(DutchFlower.Valid.VALID));
    }

    function test_keep_rate_limiting_flop_relative_rate() public {
        vat.file('ceil', 100000 * RAD);
        vat.filk(i0, 'line', 100000 * RAD);
        vow.file('rel', WAD);
        vow.file('vel', risk.totalSupply() * 2);
        vow.file('bel', block.timestamp - 1);
        vow.file('cel', 1);

        assertGt(risk.totalSupply(), WAD);
        uint risksupply = risk.totalSupply();
        prepguyrico(10000 * WAD, true);
        uint aid = vow.keep(ilks);
        assertGt(aid, 0);
        (,,address hag, uint ham, address wag, uint wam,,,,uint valid) = flow.auctions(aid);
        assertEq(hag, arisk);
        assertEq(ham, risksupply);
        assertEq(wag, arico);
        assertEq(wam, UINT256_MAX);
        assertEq(risk.totalSupply(), risksupply + risksupply);
        assertEq(valid, uint(DutchFlower.Valid.VALID));
    }

    function test_e2e_all_actions() public {
        // run a flap and ensure risk is burnt
        uint risk_initial_supply = risk.totalSupply();
        skip(BANKYEAR);
        uint256 aid = vow.keep(ilks);

        risk.mint(address(guy), 1000 * WAD);
        guy.approve(arisk, aflow, UINT256_MAX);
        feedpush(RICO_RISK_TAG, bytes32(1000 * RAY), UINT256_MAX);
        skip(3);
        guy.glug{value: rmul(block.basefee, GEL)}(aid);

        skip(60);
        vm.expectCall(address(flow), abi.encodePacked(flow.flow.selector));
        aid = vow.keep(ilks); // call again to burn risk given to vow the first time

        feedpush(RISK_RICO_TAG, bytes32(10000 * RAY), UINT256_MAX);
        risk.mint(address(guy), 1000 * WAD);
        skip(4);
        guy.glug{value: rmul(block.basefee, GEL)}(aid);
        uint risk_post_flap_supply = risk.totalSupply();
        assertLt(risk_post_flap_supply, risk_initial_supply + 1000 * WAD * 2);

        // confirm bail trades the weth for rico
        uint vow_rico_0 = rico.balanceOf(avow);
        uint vat_weth_0 = weth.balanceOf(address(hook));
        vm.expectCall(address(flow), abi.encodePacked(flow.flow.selector));
        uint bail_aid = vow.bail(i0, me);

        // collateral has been grabbed but not sold, so we flop
        vm.expectCall(address(flow), abi.encodePacked(flow.flow.selector));
        uint vow_pre_flop_rico = rico.balanceOf(avow);
        aid = vow.keep(ilks);

        feedpush(RISK_RICO_TAG, bytes32(100 * RAY), UINT256_MAX);
        skip(2);
        prepguyrico(1000 * WAD, false);
        guy.glug{value: rmul(block.basefee, GEL)}(aid);

        // now vow should hold more rico
        uint vow_post_flop_rico = rico.balanceOf(avow);
        assertGt(vow_post_flop_rico, vow_pre_flop_rico);

        // now complete the liquidation
        feedpush(wrtag, bytes32(100 * RAY), UINT256_MAX);
        guy.glug{value: rmul(block.basefee, GEL)}(bail_aid);
        uint vow_rico_1 = rico.balanceOf(avow);
        uint vat_weth_1 = weth.balanceOf(address(hook));
        assertGt(vow_rico_1, vow_rico_0);
        assertLt(vat_weth_1, vat_weth_0);
    }

    function test_flops_bounded() public {
        uint count0 = flow.count();
        skip(BANKYEAR);
        vow.keep(ilks);
        vow.keep(ilks);
        uint count1 = flow.count();
        assertEq(count0 + 1, count1);
    }
}

