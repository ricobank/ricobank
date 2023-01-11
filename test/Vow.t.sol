// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import { Ball } from '../src/ball.sol';
import { GemLike, ERC20 } from '../src/abi.sol';
import { Vat } from '../src/vat.sol';
import { Vow } from '../src/vow.sol';
import { RicoSetUp } from "./RicoHelper.sol";
import { Asset, PoolArgs } from "./BalHelper.sol";
import { BalancerFlower } from '../src/flow.sol';

contract VowTest is Test, RicoSetUp {
    uint256 public init_join = 1000;
    uint stack = WAD * 10;
    bytes32[] ilks;
    bytes32 pool_id_rico_risk;
    bytes32 pool_id_gold_rico;

    function setUp() public {
        make_bank();
        init_gold();
        ilks.push(gilk);
        rico.approve(address(flow), type(uint256).max);

        vow.grant(address(gold));

        feed.push(gtag, bytes32(RAY * 1000), block.timestamp + 1000);
        vat.frob(gilk, address(this), int(init_join * WAD), int(stack) * 1000);
        risk.mint(address(this), 10000 * WAD);

        vow.pair(agold, 'vel', 1e18);
        vow.pair(agold, 'rel', 1e12);
        vow.pair(agold, 'cel', 600);
        vow.pair(arico, 'vel', 1e18);
        vow.pair(arico, 'rel', 1e12);
        vow.pair(arico, 'cel', 600);
        vow.pair(arisk, 'vel', 1e18);
        vow.pair(arisk, 'rel', 1e12);
        vow.pair(arisk, 'cel', 600);
        vow.pair(address(0), 'vel', 1e18);
        vow.pair(address(0), 'rel', 1e12);
        vow.pair(address(0), 'cel', 600);

        // have 10k each of rico, risk and gold
        gold.approve(BAL_VAULT, type(uint256).max);
        rico.approve(BAL_VAULT, type(uint256).max);
        risk.approve(BAL_VAULT, type(uint256).max);
        gold.approve(address(flow), type(uint256).max);
        rico.approve(address(flow), type(uint256).max);
        risk.approve(address(flow), type(uint256).max);

        Asset memory gold_asset = Asset(agold, 5 * WAD / 10, 1000 * WAD);
        Asset memory rico_asset = Asset(arico, 5 * WAD / 10, 1000 * WAD);
        Asset memory risk_asset = Asset(arisk, 5 * WAD / 10, 1000 * WAD);

        PoolArgs memory rico_risk_args = PoolArgs(rico_asset, risk_asset, "mock", "MOCK", WAD / 100);
        PoolArgs memory gold_rico_args = PoolArgs(gold_asset, rico_asset, "mock", "MOCK", WAD / 100);

        pool_id_rico_risk = flow.pools(arico, arisk);
        join_pool(rico_risk_args, pool_id_rico_risk);
        pool_id_gold_rico = create_and_join_pool(gold_rico_args);

        flow.setPool(agold, arico, pool_id_gold_rico);
    }

    // goldusd, par, and liqr all = 1 after set up.
    function test_risk_ramp_is_used() public {
        // set rate of risk sales to near zero
        address[] memory tokens;
        uint256[] memory balances0;
        uint256[] memory balances1;
        uint256 lastChangeBlock;
        uint rico_index = 0;
        uint risk_index = 1;
        vow.pair(arisk, 'vel', 1);
        vow.pair(arisk, 'rel', 1);
        vow.pair(arisk, 'cel', 1);
        (tokens, balances0, lastChangeBlock) = vault.getPoolTokens(pool_id_rico_risk);
        if (arisk == tokens[0]) {
            risk_index = 0;
            rico_index = 1;
        }

        // setup frobbed to edge, dropping gold price puts system way underwater
        feed.push(gtag, bytes32(RAY), block.timestamp + 10000);

        // create the sin and kick off risk sale
        vow.bail(gilk, self);
        flow.glug(bytes32(flow.count()));
        vow.keep(ilks);
        flow.glug(bytes32(flow.count()));
        (tokens, balances1, lastChangeBlock) = vault.getPoolTokens(pool_id_rico_risk);

        // correct risk ramp usage should limit sale to one
        uint risk_sold = balances1[risk_index] - balances0[risk_index];
        assertTrue(risk_sold == 1);
    }
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
        GemLike(gem).transfer(dst, amt);
    }
}

interface WethLike is ERC20 {
    function deposit() external payable;
    function approve(address, uint) external;
    function allowance(address, address) external returns (uint);
}

contract VowJsTest is Test, RicoSetUp {
    // me == js ALI
    address me;
    Usr bob;
    Usr cat;
    address b;
    address c;
    WethLike weth;
    bytes32 poolid_weth_rico;
    bytes32 poolid_risk_rico;
    bytes32 i0;
    bytes32[] ilks;
    uint prevcount;

    function setUp() public {
        make_bank();
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

        curb(arisk, WAD, WAD / 10000, 0, 60);

        feed.push(wtag, bytes32(RAY), block.timestamp + 2 * BANKYEAR);
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

        weth.approve(address(vault), UINT256_MAX);
        rico.approve(address(vault), UINT256_MAX);
        risk.approve(address(vault), UINT256_MAX);

        poolid_weth_rico = flow.pools(WETH, arico);
        Asset memory weth_asset = Asset(WETH, 5 * WAD / 10, 2000 * WAD);
        Asset memory rico_asset = Asset(arico, 5 * WAD / 10, 2000 * WAD);
        PoolArgs memory weth_rico_args = PoolArgs(weth_asset, rico_asset, "mock", "MOCK", WAD / 100);
        join_pool(weth_rico_args, poolid_weth_rico);

        Asset memory risk_asset = Asset(arisk, 5 * WAD / 10, 2000 * WAD);
        poolid_risk_rico = flow.pools(arisk, arico);
        PoolArgs memory risk_rico_args = PoolArgs(risk_asset, rico_asset, "mock", "MOCK", WAD / 100);
        join_pool(risk_rico_args, poolid_risk_rico);

        curb(WETH, WAD, WAD / 10000, 0, 600);
        curb(arico, WAD, WAD / 10000, 0, 600);

        flow.approve_gem(arico);
        flow.approve_gem(arisk);
        flow.approve_gem(WETH);
        prevcount = flow.count();
    }

    function test_bail_urns_1yr_unsafe() public {
        skip(BANKYEAR);
        vow.keep(ilks);

        assertEq(uint(vat.safe(i0, me)), uint(Vat.Spot.Sunk));

        uint sin0 = vat.sin(avow);
        uint gembal0 = weth.balanceOf(address(flow));
        uint vow_rico0 = rico.balanceOf(avow);
        assertEq(sin0, 0);
        assertEq(gembal0, 0);
        assertEq(vow_rico0, 0);

        vm.expectCall(address(flow), abi.encodePacked(flow.flow.selector));
        vow.bail(i0, me);
        flow.glug(bytes32(flow.count()));

        (uint ink, uint art) = vat.urns(i0, me);
        uint sin1 = vat.sin(avow);
        uint gembal1 = weth.balanceOf(address(flow));
        uint vow_rico1 = rico.balanceOf(avow);
        assertEq(ink, 0);
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
        assertEq(sin0, 0);
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
        curb(arisk, WAD / 1000, 1000000 * WAD, 0, 1000);
        skip(BANKYEAR);
        vow.bail(i0, c); flow.glug(bytes32(flow.count()));
        vow.keep(ilks); flow.glug(bytes32(flow.count()));
        uint risksupply1 = risk.totalSupply();
        skip(500);
        vow.keep(ilks); flow.glug(bytes32(flow.count()));
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
        curb(arisk, 1000000 * WAD, WAD / 10000000, 0, 1000);
        skip(BANKYEAR);
        vow.bail(i0, c); flow.glug(bytes32(flow.count()));
        vow.keep(ilks); flow.glug(bytes32(flow.count()));
        uint risksupply1 = risk.totalSupply();
        skip(500);
        vow.keep(ilks); flow.glug(bytes32(flow.count()));
        uint risksupply2 = risk.totalSupply();

        // should have had a mint of the full vel*cel and then half vel*cel
        uint mint1 = risksupply1 - risksupply0;
        uint mint2 = risksupply2 - risksupply1;
        assertGe(mint1, WAD * 999 / 1000);
        assertLe(mint1, WAD);
        assertGe(mint2, WAD * 497 / 1000);
        assertLe(mint2, WAD * 510 / 1000);
    }

    function test_e2e_all_actions() public {
        // run a flap and ensure risk is burnt
        uint risk_initial_supply = risk.totalSupply();
        skip(BANKYEAR);
        vow.keep(ilks);
        flow.glug(bytes32(flow.count()));
        skip(60);
        vm.expectCall(address(flow), abi.encodePacked(flow.flow.selector));
        vow.keep(ilks); // call again to burn risk given to vow the first time
        flow.glug(bytes32(flow.count()));
        uint risk_post_flap_supply = risk.totalSupply();
        assertLt(risk_post_flap_supply, risk_initial_supply);

        // confirm bail trades the weth for rico
        uint vow_rico_0 = rico.balanceOf(avow);
        uint vat_weth_0 = weth.balanceOf(avat);
        vm.expectCall(address(flow), abi.encodePacked(flow.flow.selector));
        vow.bail(i0, me);
        flow.glug(bytes32(flow.count()));
        uint vow_rico_1 = rico.balanceOf(avow);
        uint vat_weth_1 = weth.balanceOf(avat);
        assertGt(vow_rico_1, vow_rico_0);
        assertLt(vat_weth_1, vat_weth_0);

        // although the keep joins the rico sin is still greater due to fees so we flop
        vm.expectCall(address(flow), abi.encodePacked(flow.flow.selector));
        vow.keep(ilks);
        flow.glug(bytes32(flow.count()));
        // now vow should hold more rico than anti tokens
        uint sin = vat.sin(avow);
        uint vow_rico = rico.balanceOf(avow);
        assertGt(vow_rico * RAY, sin);
    }

    function test_tiny_flap_fail() public {
        vow.pair(arico, 'del', 10000 * WAD);
        skip(BANKYEAR);
        vow.bail(i0, me);
        vm.expectRevert(BalancerFlower.ErrTinyFlow.selector);
        vow.keep(ilks);
        vow.pair(arico, 'del', 1 * WAD);
        vow.keep(ilks);
    }

    function test_tiny_flop_fail() public {
        vow.pair(arisk, 'del', 10000 * WAD);
        skip(BANKYEAR / 2);
        vow.bail(i0, me);
        vm.expectRevert(BalancerFlower.ErrTinyFlow.selector);
        vow.keep(ilks);
        vow.pair(arisk, 'del', 1 * WAD);
        vow.keep(ilks);
    }
}

