// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import { Ball } from '../src/ball.sol';
import { Gem } from '../lib/gemfab/src/gem.sol';
import { Vat } from '../src/vat.sol';
import { Vow } from '../src/vow.sol';
import { RicoSetUp, WethLike } from "./RicoHelper.sol";
import { Asset, PoolArgs } from "./UniHelper.sol";
import { UniFlower } from '../src/flow.sol';
import { Ward } from '../src/mixin/ward.sol';
import { Math } from '../src/mixin/math.sol';

contract GemUsr {
    Vat vat;
    constructor(Vat _vat) {
        vat  = _vat;
    }
    function approve(address gem, address usr, uint amt) public {
        Gem(gem).approve(usr, amt);
    }
    function frob(bytes32 ilk, address usr, int dink, int dart) public {
        vat.frob(ilk, usr, dink, dart);
    }
    function transfer(address gem, address dst, uint amt) public {
        Gem(gem).transfer(dst, amt);
    }
}



// integrated vow/flow tests
contract VowTest is Test, RicoSetUp {
    uint256 public init_join = 1000;
    uint stack = WAD * 10;
    bytes32[] ilks;
    address rico_risk_pool;

    function rico_mint(uint amt, bool bail) internal {
        GemUsr usr = new GemUsr(vat);
        (bytes32 v, uint t) = feedpull(grtag);
        feedpush(grtag, bytes32(RAY), type(uint).max);
        gold.mint(address(usr), amt);
        usr.approve(agold, avat, amt);
        usr.frob(gilk, address(usr), int(amt), int(amt));
        feedpush(grtag, bytes32(0), type(uint).max);
        if (bail) vow.bail(gilk, address(usr));
        usr.transfer(arico, self, amt);
        feedpush(grtag, v, t);
    }

    function setUp() public {
        make_bank();
        init_gold();
        ilks.push(gilk);
        rico.approve(address(flow), type(uint256).max);

        vow.grant(address(gold));

        curb(agold, 1e18, 1e12, 0, 600, 1);
        curb(arico, 1e18, 1e12, 0, 600, 1);
        curb(arisk, 1e18, 1e12, 0, 600, 1);
        curb(azero, 1e18, 1e12, 0, 600, 1);

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

        address [] memory addr2 = new address[](2);
        uint24  [] memory fees1 = new uint24 [](1);
        bytes memory fore;
        bytes memory rear;
        addr2[0] = agold;
        addr2[1] = arico;
        fees1[0] = 3000;
        (fore, rear) = create_path(addr2, fees1);
        flow.setPath(agold, arico, fore, rear);
    }

    // goldusd, par, and liqr all = 1 after set up.
    function test_risk_ramp_is_used() public {
        feedpush(grtag, bytes32(RAY * 1000), block.timestamp + 1000);
        vat.frob(gilk, address(this), int(init_join * WAD), int(stack) * 1000);
 
        // set rate of risk sales to near zero
        // set mint ramp higher to use risk ramp
        curb(azero, WAD, WAD, block.timestamp - 1, 1, 1);
        curb(arisk, 1, 1, block.timestamp - 1, 1, 1);
        uint256 pool_risk_0 = risk.balanceOf(rico_risk_pool);

        // setup frobbed to edge, dropping gold price puts system way underwater
        feedpush(grtag, bytes32(RAY), block.timestamp + 10000);

        // create the sin and kick off risk sale
        uint256 aid = vow.bail(gilk, self);
        flow.glug(aid);
        aid = vow.keep(ilks);
        flow.glug(aid);
        uint256 pool_risk_1 = risk.balanceOf(rico_risk_pool);

        // correct risk ramp usage should limit sale to one
        uint risk_sold = pool_risk_1 - pool_risk_0;
        assertTrue(risk_sold == 1);
    }

    function test_wards() public {
        vow.flowback(0, 0);
        vow.pair(address(0), 'vel', WAD);
        vow.link('flow', address(flow));

        vow.give(address(0));

        vm.expectRevert();
        vow.flowback(0, 0);
        vow.grant(arico);
        vm.expectRevert();
        vow.pair(address(0), 'vel', WAD);
        vm.expectRevert();
        vow.link('flow', address(flow));

        vow.keep(ilks);
        vat.frob(gilk, self, int(WAD), int(WAD));
        vm.expectRevert(Vow.ErrSafeBail.selector);
        vow.bail(gilk, self);
    }

    function test_flowback() public {
        curb(agold, 100000 * WAD, WAD, 0, 1, 1);
        (uint ink, uint art) = vat.urns(gilk, self);
        feedpush(grtag, bytes32(1000000 * RAY), type(uint).max);
        vat.frob(gilk, self, int(WAD), int(WAD / 2));

        feedpush(grtag, bytes32(0), type(uint).max);
        uint aid = vow.bail(gilk, self);

        (ink,) = vat.urns(gilk, self);
        assertEq(ink, 0);
        flow.glug(aid);

        (ink, art) = vat.urns(gilk, self);
        assertEq(art, 0);
        assertGt(ink, 0);

        // sale gone
        (bytes32 saleilk, address saleurn) = vow.sales(aid);
        assertEq(saleilk, bytes32(0));
        assertEq(saleurn, azero);
    }

    // these next few maybe belong in flow tests...
    // first glug covers the debt without remainder, flowback with high del
    // (exact out)
    uint del_test_endink = 498493239915892134;
    function test_tiny_flowback() public {
        curb(agold, WAD * 3 / 4, WAD, 0, 1, WAD / 4 + 1); // high del

        feedpush(grtag, bytes32(1000000 * RAY), type(uint).max);
        vat.frob(gilk, self, int(WAD), int(WAD / 2));

        feedpush(grtag, bytes32(0), type(uint).max);
        uint aid = vow.bail(gilk, self);

        flow.glug(aid);
        vm.expectRevert(UniFlower.ErrEmptyAid.selector);
        flow.glug(aid);
        (uint ink, uint art) = vat.urns(gilk, self);

        (ink, art) = vat.urns(gilk, self);
        assertEq(art, 0);
        // hardcoding this to use in test_del_flowback
        assertEq(ink, del_test_endink);

        // sale gone
        (bytes32 saleilk, address saleurn) = vow.sales(aid);
        assertEq(saleilk, bytes32(0));
        assertEq(saleurn, azero);
    }

    // first glug covers the debt without remainder, flowback with low del
    // (exact out)
    function test_del_flowback() public {
        curb(agold, WAD * 3 / 4, WAD, 0, 1, WAD / 8); // low del

        feedpush(grtag, bytes32(1000000 * RAY), type(uint).max);
        vat.frob(gilk, self, int(WAD), int(WAD / 2));

        feedpush(grtag, bytes32(0), type(uint).max);
        uint aid = vow.bail(gilk, self);

        flow.glug(aid);
        vm.expectRevert(UniFlower.ErrEmptyAid.selector);
        flow.glug(aid);

        (uint ink, uint art) = vat.urns(gilk, self);
        assertEq(art, 0);
        // hardcoding to reuse use in test_del_flowback
        assertEq(ink, del_test_endink);

        // sale gone
        (bytes32 saleilk, address saleurn) = vow.sales(aid);
        assertEq(saleilk, bytes32(0));
        assertEq(saleurn, azero);
    }

    // first glug covers the debt with remainder, flowback with high del
    function test_del_nocover_then_flowback() public {
        curb(agold, WAD * 2 / 3, WAD, 0, 1, WAD / 2); // high del

        feedpush(grtag, bytes32(1000000 * RAY), type(uint).max);
        vat.frob(gilk, self, int(WAD), int(WAD * 9 / 10));

        feedpush(grtag, bytes32(0), type(uint).max);
        uint aid = vow.bail(gilk, self);
        (uint ink, uint art) = vat.urns(gilk, self);
        assertEq(ink, 0);
        assertEq(art, 0);

        flow.glug(aid);
        skip(1);
        vm.expectRevert(UniFlower.ErrEmptyAid.selector);
        flow.glug(aid);

        (ink, art) = vat.urns(gilk, self);
        assertEq(ink, 97284596799900971); 
        assertEq(art, 0);

        // sale gone
        (bytes32 saleilk, address saleurn) = vow.sales(aid);
        assertEq(saleilk, bytes32(0));
        assertEq(saleurn, azero);
    }

    // first glug could cover the debt with remainder, but del low
    function test_first_glug_could_cover_low_del() public {
        curb(agold, WAD * 2 / 3, WAD, 0, 1, WAD / 100); // low del

        feedpush(grtag, bytes32(1000000 * RAY), type(uint).max);
        vat.frob(gilk, self, int(WAD), int(WAD * 9 / 10));

        feedpush(grtag, bytes32(0), type(uint).max);
        uint aid = vow.bail(gilk, self);
        (uint ink, uint art) = vat.urns(gilk, self);
        assertEq(ink, 0);
        assertEq(art, 0);

        flow.glug(aid);
        skip(1);
        flow.glug(aid);

        (ink, art) = vat.urns(gilk, self);
        assertEq(ink, 97284596799900971); 
        assertEq(art, 0);

        // sale gone
        (bytes32 saleilk, address saleurn) = vow.sales(aid);
        assertEq(saleilk, bytes32(0));
        assertEq(saleurn, azero);
    }

    // can't bail 2**255, but can keep 2**255
    function test_flowback_negative_one() public {
        uint UINT_NEG_ONE = 2 ** 255;
        curb(agold, WAD, WAD, 0, 1, 0);
        feedpush(grtag, bytes32(1000000 * RAY), type(uint).max);
        vat.frob(gilk, self, int(WAD), int(WAD));
        skip(BANKYEAR * 1000);
        uint aid = vow.bail(gilk, self);
        // with both mints, should end up with totalSupply
        // around UINT_NEG_ONE*3/4
        risk.mint(self, UINT_NEG_ONE / 2);
        curb(azero, UINT_NEG_ONE, 3 * WAD, 0, 1, 0);
        curb(arisk, UINT_NEG_ONE, WAD, 0, 1, 0);

        // should fail to wmul(rel, totalSupply) in clip
        // making such high refunds impossible
        // todo error selector once math has proper errors
        vm.expectRevert();
        vow.keep(ilks);

        // ok but flowback from here instead...
        // todo vat test to show UINT_NEG_ONE ink impossible
        vm.expectRevert(Vow.ErrBigFlowback.selector);
        vow.flowback(aid, 2 ** 255);
        // should fail from rad conversion in safe
        // todo error selector once math has proper errors
        vm.expectRevert();
        vow.flowback(aid, 2 ** 255 - 1);
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
            vow.flowback(aid_rf, 2);
        }
    }

    function test_reentrant_flowback() public {
        curb(agold, WAD, WAD, 0, 1, 0);
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
        vow.flowback(aid_rf, 2);
        assertEq(uint(lastilk_rf), 0);
        assertEq(uint160(lasturn_rf), 0);
    }

    function test_drip() public {
        (,,,,,,,uint rho,,,,) = vat.ilks(gilk);
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
        (address vow, address hag, uint ham, address wag, uint wam) = flow.auctions(aid);
        assertEq(hag, arico);
        assertEq(ham, 1);
        assertEq(vat.sin(avow), RAY);
        assertGt(aid, 0);

        assertEq(vow, avow);
        assertEq(wag, arisk);
        assertEq(wam, type(uint).max);
    }

    function test_keep_unbalanced_slightly_more_sin() public {
        vat.filk(gilk, 'fee', 2 * RAY);

        feedpush(grtag, bytes32(RAY * 1000), block.timestamp + 1000);
        uint amt = vat.sin(avow) / RAY - 1;
        vat.frob(gilk, address(this), int(amt), int(amt));
        skip(1);

        feedpush(grtag, bytes32(0), block.timestamp + 10000);

        assertEq(rico.balanceOf(avow), 0);
        (,uint flop,) = flow.clip(avow, azero, arisk, type(uint).max);
        assertGt(flop, 0);
        uint256 aid = vow.keep(ilks);
        assertEq(rico.balanceOf(avow), 1);
        assertEq(vat.sin(avow), 2 * RAY);
        assertGt(aid, 0);
        (address vow, address hag, uint ham, address wag, uint wam) = flow.auctions(aid);
        assertEq(hag, arisk);
        assertEq(ham, flop);

        assertEq(vow, avow);
        assertEq(wag, arico);
        assertEq(wam, type(uint).max);
    }

    function test_bail_hook() public {
        Hook hook = new Hook();
        vat.filk(gilk, 'hook', uint(bytes32(bytes20(address(hook)))));
        bytes memory hookdata = abi.encodeCall(
            hook.hook,
            (avow, abi.encodeCall(vat.grab, (gilk, self, -int(WAD), -int(WAD))))
        );

        feedpush(grtag, bytes32(RAY * 1000000), type(uint).max);
        vat.frob(gilk, self, int(WAD), int(WAD));
        feedpush(grtag, bytes32(0), type(uint).max);
        uint vowgoldbefore = gold.balanceOf(avow);
        vm.expectCall(address(hook), hookdata);
        uint aid = vow.bail(gilk, self);
        assertEq(gold.balanceOf(avow), vowgoldbefore);
        assertEq(aid, 0);
    }

}

contract Hook {
    uint public hooks;
    function hook(address, bytes calldata) public {}
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
        weth.approve(avat, UINT256_MAX);

        vat.file('ceil', 10000 * RAD);
        vat.filk(i0, 'line', 10000 * RAD);
        vat.filk(i0, 'chop', RAY * 11 / 10);

        curb(arisk, WAD, WAD / 10000, 0, 60, 1);
        curb(azero, WAD, WAD / 10000, 0, 60, 1);

        feedpush(wrtag, bytes32(RAY), block.timestamp + 2 * BANKYEAR);
        uint fee = 1000000001546067052200000000; // == ray(1.05 ** (1/BANKYEAR))
        vat.filk(i0, 'fee', fee);
        vat.frob(i0, me, int(100 * WAD), 0);
        vat.frob(i0, me, 0, int(99 * WAD));

        uint bal = rico.balanceOf(me);
        assertEq(bal, 99 * WAD);
        Vat.Spot safe1 = vat.safe(i0, me);
        assertEq(uint(safe1), uint(Vat.Spot.Safe));

        cat.deposit{value: 7000 * WAD}();
        cat.approve(avat, UINT256_MAX);
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

        curb(WETH, WAD, WAD / 10000, 0, 600, 1);
        curb(arico, WAD, WAD / 10000, 0, 600, 1);

        flow.approve_gem(arico);
        flow.approve_gem(arisk);
        flow.approve_gem(DAI);
        flow.approve_gem(WETH);
        prevcount = flow.count();

        curb(azero, 200 * WAD, WAD, block.timestamp, 1, 1);
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

        flow.glug(aid);
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
        uint risksupply0 = risk.totalSupply();
        vat.filk(i0, 'fee', 1000000021964508878400000000);  // ray(2 ** (1/BANKYEAR)
        curb(arisk, WAD, 1000000 * WAD, 0, 1000, 1);
        curb(azero, WAD / 1000, 1000000 * WAD, 0, 1000, 1); // mint ramp < risk ramp
        skip(BANKYEAR);
        uint256 aid = vow.bail(i0, c); flow.glug(aid);
        aid = vow.keep(ilks); flow.glug(aid);
        uint risksupply1 = risk.totalSupply();
        skip(500);
        aid = vow.keep(ilks); flow.glug(aid);
        uint risksupply2 = risk.totalSupply();

        // should have had a mint of the full vel*cel and then half vel*cel
        uint mint1 = risksupply1 - risksupply0;
        uint mint2 = risksupply2 - risksupply1;
        assertGe(mint1, WAD * 99 / 100);
        assertLe(mint1, WAD * 101 / 100);
        assertGe(mint2, WAD * 49 / 100);
        assertLe(mint2, WAD * 51 / 100);
    }

    function test_keep_rate_limiting_flop_relative_rate() public {
        uint risksupply0 = risk.totalSupply();
        vat.filk(i0, 'fee', 1000000021964508878400000000);
        // for same results as above the rel rate is set to 1 / risk supply * vel used above
        curb(arisk, 1000000 * WAD, WAD / 1000000, 0, 1000, 1);
        curb(azero, 1000000 * WAD, WAD / 10000000, 0, 1000, 1); // mint ramp < risk ramp
        skip(BANKYEAR);
        uint256 aid = vow.bail(i0, c); flow.glug(aid);
        aid = vow.keep(ilks); flow.glug(aid);
        uint risksupply1 = risk.totalSupply();
        skip(500);
        aid = vow.keep(ilks); flow.glug(aid);
        uint risksupply2 = risk.totalSupply();

        // should have had a mint of the full vel*cel and then half vel*cel
        uint mint1 = risksupply1 - risksupply0;
        uint mint2 = risksupply2 - risksupply1;
        assertEq(mint1, risksupply0 / 10000000 * 1000);
        assertEq(mint2, risksupply1 / 10000000 * 500);
    }

    function test_e2e_all_actions() public {
        // run a flap and ensure risk is burnt
        uint risk_initial_supply = risk.totalSupply();
        skip(BANKYEAR);
        uint256 aid = vow.keep(ilks);
        flow.glug(aid);
        skip(60);
        vm.expectCall(address(flow), abi.encodePacked(flow.flow.selector));
        aid = vow.keep(ilks); // call again to burn risk given to vow the first time
        flow.glug(aid);
        uint risk_post_flap_supply = risk.totalSupply();
        assertLt(risk_post_flap_supply, risk_initial_supply);

        // confirm bail trades the weth for rico
        uint vow_rico_0 = rico.balanceOf(avow);
        uint vat_weth_0 = weth.balanceOf(avat);
        vm.expectCall(address(flow), abi.encodePacked(flow.flow.selector));
        uint bail_aid = vow.bail(i0, me);

        // collateral has been grabbed but not sold, so we flop
        vm.expectCall(address(flow), abi.encodePacked(flow.flow.selector));
        uint vow_pre_flop_rico = rico.balanceOf(avow);
        aid = vow.keep(ilks);
        flow.glug(aid);

        // now vow should hold more rico
        uint vow_post_flop_rico = rico.balanceOf(avow);
        assertGt(vow_post_flop_rico, vow_pre_flop_rico);

        // now complete the liquidation
        flow.glug(bail_aid);
        uint vow_rico_1 = rico.balanceOf(avow);
        uint vat_weth_1 = weth.balanceOf(avat);
        assertGt(vow_rico_1, vow_rico_0);
        assertLt(vat_weth_1, vat_weth_0);
    }

    function test_tiny_flap_fail() public {
        vow.pair(arico, 'del', 10000 * WAD);
        skip(BANKYEAR);
        vow.bail(i0, me);
        vm.expectRevert(UniFlower.ErrTinyFlow.selector);
        vow.keep(ilks);
        vow.pair(arico, 'del', 1 * WAD);
        vow.keep(ilks);
    }

    function test_tiny_flop_fail() public {
        vow.pair(arisk, 'del', 10000 * WAD);
        skip(BANKYEAR / 2);
        vow.bail(i0, me);
        vm.expectRevert(UniFlower.ErrTinyFlow.selector);
        vow.keep(ilks);
        vow.pair(arisk, 'del', 1 * WAD);
        vow.keep(ilks);
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

