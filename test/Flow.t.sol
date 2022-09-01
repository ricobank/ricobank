// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import "forge-std/Test.sol";

import '../src/mixin/math.sol';
import { Ball } from '../src/ball.sol';
import { BalancerFlower } from '../src/flow.sol';
import { Flow, Flowback, GemLike } from '../src/abi.sol';
import { RicoSetUp } from "./RicoHelper.sol";
import { Asset, BalSetUp, PoolArgs } from "./BalHelper.sol";

contract FlowTest is Test, RicoSetUp, BalSetUp, Math, Flowback {
    Ball ball;
    BalancerFlower flow;
    GemLike rico;
    GemLike risk;
    uint rico_index = 0;
    uint risk_index = 1;
    uint back_count = 0;
    bytes32 pool_id_rico_risk;

    function setUp() public {
        ball = make_bank();
        flow = ball.flow();
        rico = GemLike(address(ball.rico()));
        risk = GemLike(address(ball.risk()));
        rico.mint(address(this), 10000 * WAD);
        risk.mint(address(this), 10000 * WAD);
        rico.approve(BAL_VAULT, type(uint256).max);
        risk.approve(BAL_VAULT, type(uint256).max);
        rico.approve(address(flow), type(uint256).max);
        risk.approve(address(flow), type(uint256).max);
        Asset memory rico_asset = Asset(address(ball.rico()), 5 * WAD / 10, 1000 * WAD);
        Asset memory risk_asset = Asset(address(ball.risk()), 5 * WAD / 10, 1000 * WAD);
        PoolArgs memory rico_risk_args = PoolArgs(rico_asset, risk_asset, "mock", "MOCK", WAD / 100);
        pool_id_rico_risk = create_pool(rico_risk_args);
        flow.setPool(address(rico), address(risk), pool_id_rico_risk);
        flow.setPool(address(risk), address(rico), pool_id_rico_risk);
        flow.setVault(BAL_VAULT);
        flow.approve_gem(address(rico));
        flow.approve_gem(address(risk));
        if (address(rico) > address(risk)) {
            risk_index = 0;
            rico_index = 1;
        }
    }

    function flowback(bytes32 aid, address gem, uint refund) external {
        back_count += 1;
    }

    function test_recharge_velocity() public {
        // recharge at 1/s up to 100s, limit is abs, rel much higher
        flow.curb(address(rico), 'vel', WAD);
        flow.curb(address(rico), 'rel', WAD * 100000);
        flow.curb(address(rico), 'cel', 100);

        address[] memory tokens;
        uint256[] memory balances0;
        uint256[] memory balances1;
        uint256[] memory balances2;
        uint256[] memory balances3;
        uint256 lastChangeBlock;

        // create sale of 1k rico for as much risk as it can get
        uint256 back_pre_flow_rico = rico.balanceOf(address(this));
        bytes32 aid = flow.flow(address(rico), WAD * 1000, address(risk), type(uint256).max);
        uint256 back_post_flow_rico = rico.balanceOf(address(this));
        assertEq(back_pre_flow_rico, back_post_flow_rico + 1000*WAD);
        (tokens, balances0, lastChangeBlock) = vault.getPoolTokens(pool_id_rico_risk);
        uint256 back_risk_1 = risk.balanceOf(address(this));

        // flow glugs once to empty ramps charge
        flow.glug(aid);
        (tokens, balances1, lastChangeBlock) = vault.getPoolTokens(pool_id_rico_risk);
        assertEq(balances0[rico_index], balances1[rico_index] - 100*WAD);
        uint256 back_risk_2 = risk.balanceOf(address(this));
        assertGt(back_risk_2, back_risk_1 + 80*WAD);  // 80 is some significant portion of 100 but less due to slippage

        // instant repeat should revert (BAL#510, zero amount in)
        vm.expectRevert('Flow/swap');
        flow.glug(aid);
        (tokens, balances2, lastChangeBlock) = vault.getPoolTokens(pool_id_rico_risk);
        assertEq(balances1[rico_index], balances2[rico_index]);

        // wait half recharge period and half max charge should be swapped
        skip(50);
        flow.glug(aid);
        (tokens, balances3, lastChangeBlock) = vault.getPoolTokens(pool_id_rico_risk);
        assertEq(balances1[rico_index], balances3[rico_index] - 50*WAD);

        assertEq(back_count, 0);
    }

    function test_recharge_relative_velocity() public {
        // recharge at 1/s up to 100s, limit is abs, rel much higher
        // rate should be equal to above test as 10k tokens exist, this time rel provides limit
        flow.curb(address(rico), 'vel', WAD * 10000);
        flow.curb(address(rico), 'rel', WAD / 10000);
        flow.curb(address(rico), 'cel', 100);

        address[] memory tokens;
        uint256[] memory balances0;
        uint256[] memory balances1;
        uint256[] memory balances2;
        uint256[] memory balances3;
        uint256 lastChangeBlock;

        // create sale of 1k rico for as much risk as it can get
        uint256 back_pre_flow_rico = rico.balanceOf(address(this));
        bytes32 aid = flow.flow(address(rico), WAD * 1000, address(risk), type(uint256).max);
        uint256 back_post_flow_rico = rico.balanceOf(address(this));
        assertEq(back_pre_flow_rico, back_post_flow_rico + 1000*WAD);
        (tokens, balances0, lastChangeBlock) = vault.getPoolTokens(pool_id_rico_risk);
        uint256 back_risk_1 = risk.balanceOf(address(this));

        // flow glugs once to empty ramps charge
        flow.glug(aid);
        (tokens, balances1, lastChangeBlock) = vault.getPoolTokens(pool_id_rico_risk);
        assertEq(balances0[rico_index], balances1[rico_index] - 100*WAD);
        uint256 back_risk_2 = risk.balanceOf(address(this));
        assertGt(back_risk_2, back_risk_1 + 80*WAD);  // 80 is some significant portion of 100 but less due to slippage

        // instant repeat should revert (BAL#510, zero amount in)
        vm.expectRevert('Flow/swap');
        flow.glug(aid);
        (tokens, balances2, lastChangeBlock) = vault.getPoolTokens(pool_id_rico_risk);
        assertEq(balances1[rico_index], balances2[rico_index]);

        // wait half recharge period and half max charge should be swapped
        skip(50);
        flow.glug(aid);
        (tokens, balances3, lastChangeBlock) = vault.getPoolTokens(pool_id_rico_risk);
        assertEq(balances1[rico_index], balances3[rico_index] - 50*WAD);

        assertEq(back_count, 0);
    }

    function test_refund() public {
        flow.curb(address(rico), 'vel', WAD);
        flow.curb(address(rico), 'rel', WAD * 100000);
        flow.curb(address(rico), 'cel', 100);

        // create sale of 1k rico for 200 risk, three glugs should reach want amount
        uint256 back_pre_flow_rico = rico.balanceOf(address(this));
        bytes32 aid = flow.flow(address(rico), WAD * 1000, address(risk), WAD * 200);
        uint256 back_post_flow_rico = rico.balanceOf(address(this));
        assertEq(back_pre_flow_rico, back_post_flow_rico + 1000*WAD);
        uint256 back_risk_1 = risk.balanceOf(address(this));

        // complete sale and test flowback gets called exactly once
        flow.glug(aid);
        skip(100);
        flow.glug(aid);
        assertEq(back_count, 0);
        skip(100);
        flow.glug(aid);
        assertEq(back_count, 1);

        uint256 back_risk_2 = risk.balanceOf(address(this));
        uint256 back_final_rico = rico.balanceOf(address(this));

        // assert sensible refund quantity
        assertGt(back_final_rico, back_post_flow_rico + 700*WAD);
        // assert back has gained all risk wanted
        assertEq(back_risk_2, back_risk_1 + 200*WAD);

        // further glug attempts with same aid should fail
        skip(100);
        vm.expectRevert();
        flow.glug(aid);
    }

    function testFail_selling_without_paying() public {
        flow.curb(address(rico), 'vel', WAD);
        flow.curb(address(rico), 'rel', WAD * 100000);
        flow.curb(address(rico), 'cel', 100);
        flow.flow(address(rico), WAD * 100000, address(risk), type(uint256).max);
    }

    function test_dust() public {
        flow.curb(address(rico), 'vel', WAD);
        flow.curb(address(rico), 'rel', WAD * 100000);
        flow.curb(address(rico), 'cel', 100);
        flow.curb(address(rico), 'del', WAD * 20);

        address[] memory tokens;
        uint256[] memory balances0;
        uint256[] memory balances1;
        uint256[] memory balances2;
        uint256[] memory balances3;
        uint256 lastChangeBlock;

        // create sale of 110 rico for as much risk as it can get
        uint256 back_pre_flow_rico = rico.balanceOf(address(this));
        bytes32 aid = flow.flow(address(rico), WAD * 110, address(risk), type(uint256).max);
        uint256 back_post_flow_rico = rico.balanceOf(address(this));
        assertEq(back_pre_flow_rico, back_post_flow_rico + 110*WAD);
        (tokens, balances0, lastChangeBlock) = vault.getPoolTokens(pool_id_rico_risk);
        uint256 back_risk_1 = risk.balanceOf(address(this));

        // the sale would leave 10 behind, < del of 20
        // so the entire quantity should get delivered
        flow.glug(aid);
        (tokens, balances1, lastChangeBlock) = vault.getPoolTokens(pool_id_rico_risk);
        assertEq(balances0[rico_index], balances1[rico_index] - 110*WAD);
        uint256 back_risk_2 = risk.balanceOf(address(this));
        assertGt(back_risk_2, back_risk_1 + 80*WAD);

        // the sale should be complete
        assertEq(back_count, 1);

        // selling has gone over capacity, bell should be in the future
        // should have to wait 10 secs until charge > 0
        skip(9);
        aid = flow.flow(address(rico), WAD * 50, address(risk), type(uint256).max);
        vm.expectRevert(stdError.arithmeticError);
        flow.glug(aid);
        skip(2);
        flow.glug(aid);
    }

    function test_repeat_and_concurrant_sales() public {
    }

    function test_other() public {
    }
}
