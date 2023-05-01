// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import '../src/mixin/math.sol';
import { Ball } from '../src/ball.sol';
import { DutchFlower } from '../src/flow.sol';
import { Gem } from '../lib/gemfab/src/gem.sol';
import { Feedbase } from '../lib/feedbase/src/Feedbase.sol';
import { RicoSetUp, Guy } from "./RicoHelper.sol";
import { Asset, PoolArgs } from "./UniHelper.sol";
import { Lock } from '../src/mixin/lock.sol';
import { OverrideableGem } from './mixin/OverrideableGem.sol';
import { Vat } from '../src/vat.sol';

interface Flowback {
    function flowback(uint256 aid, uint refund) external;
}

contract FlowTest is Test, Math {
    uint256 back_count = 0;
    address rico_risk_pool;
    Guy guy;
    KindaVow vow;
    DutchFlower flow;
    address payable immutable self = payable(address(this));
    Gem rico;
    Gem risk;
    address arico;
    address arisk;
    address avow;
    address aflow;
    uint constant public STEP = RAY / 2;
    uint constant public BAR  = type(uint).max / RAY;
    uint constant public glug_delay = 5;
    bytes32 constant RICO_RISK_TAG = 'ricorisk';
    Feedbase feed;
    bool sendreverts;
    bool rxdone;
    uint UEL = 2 * RAY;

    receive () payable external {
        if (sendreverts) revert('uh oh');
        rxdone = true;
    }

    function setUp() public {
        rico = new Gem("rico", "rico");
        risk = new Gem("risk", "risk");
        arico = address(rico);
        arisk = address(risk);

        vow = new KindaVow();
        flow = new DutchFlower();
        guy = new Guy(address(new Vat()), address(flow));

        aflow = address(flow);
        avow = address(vow);

        rico.mint(self, 1000000 * WAD);
        risk.mint(self, 1000000 * WAD);
        rico.approve(address(flow), type(uint256).max);
        risk.approve(address(flow), type(uint256).max);
        feed = new Feedbase();

        flow.curb(arico, 'fel', RAY / 2);
        flow.curb(arico, 'gel', 1000 * RAY);
        flow.curb(arico, 'del', 1);
        flow.curb(arico, 'uel', UEL);
        flow.curb(arico, 'feed', uint(uint160(address(feed))));
        flow.curb(arico, 'fsrc', uint(uint160(address(self))));
        flow.curb(arico, 'ftag', uint(RICO_RISK_TAG));
    }

    function flowback(uint256, uint) external {
        back_count += 1;
    }

    function test_refund() public {
        // create sale of 1k rico for 200 risk
        uint ricoself = rico.balanceOf(self);
        // raise uel a little bit to test `fel`
        flow.curb(arico, 'uel', 4 * RAY);
        feed.push(RICO_RISK_TAG, bytes32(RAY / 5 * 4), UINT256_MAX);
        uint256 aid = flow.flow(
            avow, address(rico), WAD * 1000, address(risk), WAD * 200, self
        );
        assertEq(rico.balanceOf(avow), 0);
        assertEq(rico.balanceOf(self), ricoself - 1000 * WAD);

        // complete sale and test flowback gets called exactly once
        skip(1 + glug_delay);
        risk.transfer(address(guy), WAD * 1000);
        guy.approve(arisk, aflow, UINT256_MAX);
        uint ricoguy = rico.balanceOf(address(guy));
        ricoself = rico.balanceOf(self);
        uint riskvow = risk.balanceOf(avow);
        guy.glug{value: rmul(1000 * RAY, block.basefee)}(aid);
        assertEq(rico.balanceOf(self), ricoself + 500 * WAD);
        assertEq(back_count, 1);
        assertEq(rico.balanceOf(address(guy)), ricoguy + 500 * WAD);
        assertEq(risk.balanceOf(address(avow)), riskvow + 200 * WAD);
    }

    function test_glug_delay() public {
        // create sale of 1k rico for 200 risk
        feed.push(RICO_RISK_TAG, bytes32(RAY / 5 * 4), UINT256_MAX);
        uint256 aid = flow.flow(
            avow, address(rico), WAD * 1000, address(risk), WAD * 200, self
        );

        // complete sale and test flowback gets called exactly once
        risk.transfer(address(guy), WAD * 1000);
        guy.approve(arisk, aflow, UINT256_MAX);
        sendreverts = true;

        skip(glug_delay - 1);
        vm.expectRevert(stdError.arithmeticError);
        guy.glug{value: rmul(1000 * RAY, block.basefee)}(aid);

        skip(1);
        guy.glug{value: rmul(1000 * RAY, block.basefee)}(aid);
    }

    function test_reward_revert() public {
        // create sale of 1k rico for 200 risk
        feed.push(RICO_RISK_TAG, bytes32(RAY / 5 * 4), UINT256_MAX);
        uint256 aid = flow.flow(
            avow, address(rico), WAD * 1000, address(risk), WAD * 200, self
        );

        // complete sale and test flowback gets called exactly once
        skip(1 + glug_delay);
        risk.transfer(address(guy), WAD * 1000);
        guy.approve(arisk, aflow, UINT256_MAX);
        sendreverts = true;
        guy.glug{value: rmul(1000 * RAY, block.basefee)}(aid);

        (,,,,,,,,,,uint valid) = flow.auctions(aid);
        assertEq(valid, uint(DutchFlower.Valid.INVALID));
    }

    function test_reward_outofgas() public {
        // create sale of 1k rico for 200 risk
        feed.push(RICO_RISK_TAG, bytes32(RAY / 5 * 4), UINT256_MAX);
        uint256 aid = flow.flow(
            avow, address(rico), WAD * 1000, address(risk), WAD * 200, self
        );

        // complete sale and test flowback gets called exactly once
        skip(1 + glug_delay);
        risk.transfer(address(guy), WAD * 1000);
        guy.approve(arisk, aflow, UINT256_MAX);
        guy.glug{value: rmul(1000 * RAY, block.basefee)}(aid);
        assertEq(rxdone, false);

        (,,,,,,,,,,uint valid) = flow.auctions(aid);
        assertEq(valid, uint(DutchFlower.Valid.INVALID));
    }
 

    function test_selling_without_paying() public {
        flow.curb(arico, 'fel', RAY / 10);
        rico.approve(address(flow), 0);
        vm.expectRevert(Gem.ErrUnderflow.selector);
        flow.flow(self, arico, WAD * 1000000, address(risk), type(uint256).max, self);
    }

    // similar to test_refund, but del=0 so it is treated as a non native token
    function test_nongem() public {
        flow.curb(arico, 'del', 0);
        // raise uel a little bit to test `fel`
        flow.curb(arico, 'uel', 4 * RAY);
        // create sale of 1k rico for 200 risk
        uint ricoself = rico.balanceOf(self);
        feed.push(RICO_RISK_TAG, bytes32(RAY / 5 * 4), UINT256_MAX);
        uint256 aid = flow.flow(
            avow, address(rico), WAD * 1000, address(risk), WAD * 200, self
        );
        // doesn't change, kept in flo
        assertEq(rico.balanceOf(self), ricoself);

        // complete sale and test flowback gets called exactly once
        skip(1 + glug_delay);
        risk.transfer(address(guy), WAD * 1000);
        guy.approve(arisk, aflow, UINT256_MAX);
        uint ricoguy = rico.balanceOf(address(guy));
        uint riskvow = risk.balanceOf(avow);
        guy.glug{value: rmul(1000 * RAY, block.basefee)}(aid);
        assertEq(rico.balanceOf(self), ricoself - 500 * WAD);
        assertEq(back_count, 1);
        assertEq(rico.balanceOf(address(guy)), ricoguy + 500 * WAD);
        assertEq(risk.balanceOf(address(avow)), riskvow + 200 * WAD);
    }

}

contract KindaVow {}
