// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import '../src/mixin/math.sol';
import { Ball } from '../src/ball.sol';
import { UniFlower } from '../src/flow.sol';
import { Gem } from '../lib/gemfab/src/gem.sol';
import { RicoSetUp } from "./RicoHelper.sol";
import { Asset, PoolArgs } from "./UniHelper.sol";
import { Lock } from '../src/mixin/lock.sol';

interface Flowback {
    function flowback(uint256 aid, uint refund) external;
}

contract FlowTest is Test, RicoSetUp {
    uint256 back_count = 0;
    address rico_risk_pool;

    function setUp() public {
        make_bank();
        rico.mint(self, 1000000 * WAD);
        risk.mint(self, 1000000 * WAD);
        rico.approve(router, type(uint256).max);
        risk.approve(router, type(uint256).max);
        rico.approve(address(flow), type(uint256).max);
        risk.approve(address(flow), type(uint256).max);
        rico_risk_pool = getPoolAddr(arico, arisk, 3000);
        PoolArgs memory rico_risk_args = getArgs(arico, 100000 * WAD, arisk, 100000 * WAD, 3000, x96(1));
        join_pool(rico_risk_args);
    }

    function flowback(uint256, uint) external {
        back_count += 1;
    }

    function test_recharge_velocity() public {
        // recharge at 1/s up to 100s, limit is abs, rel much higher
        flow.curb(address(rico), 'vel', WAD);
        flow.curb(address(rico), 'rel', WAD * 100000);
        flow.curb(address(rico), 'cel', 100);

        // create sale of 1k rico for as much risk as it can get
        uint256 back_pre_flow_rico = rico.balanceOf(self);
        uint256 aid = flow.flow(address(rico), WAD * 1000, address(risk), type(uint256).max);
        uint256 back_post_flow_rico = rico.balanceOf(self);
        assertEq(back_pre_flow_rico, back_post_flow_rico + 1000*WAD);
        uint256 pool_rico_0 = rico.balanceOf(rico_risk_pool);
        uint256 back_risk_1 = risk.balanceOf(self);

        // flow glugs once to empty ramps charge
        flow.glug(aid);
        uint256 pool_rico_1 = rico.balanceOf(rico_risk_pool);
        assertEq(pool_rico_0, pool_rico_1 - 100*WAD);
        uint256 back_risk_2 = risk.balanceOf(self);
        assertGt(back_risk_2, back_risk_1 + 80*WAD);  // 80 is some significant portion of 100 but less due to slippage

        // instant repeat should revert
        vm.expectRevert(UniFlower.ErrSwapFail.selector);
        flow.glug(aid);
        uint256 pool_rico_2 = rico.balanceOf(rico_risk_pool);
        assertEq(pool_rico_1, pool_rico_2);

        // wait half recharge period and half max charge should be swapped
        skip(50);
        flow.glug(aid);
        uint256 pool_rico_3 = rico.balanceOf(rico_risk_pool);
        assertEq(pool_rico_1, pool_rico_3 - 50*WAD);

        assertEq(back_count, 0);
    }

    function test_recharge_relative_velocity() public {
        // recharge at 1/s up to 100s, limit is abs, rel much higher
        // rate should be equal to above test as 10k tokens exist, this time rel provides limit
        flow.curb(address(rico), 'vel', WAD * 10000);
        flow.curb(address(rico), 'rel', WAD / 1000000);
        flow.curb(address(rico), 'bel', block.timestamp);
        flow.curb(address(rico), 'cel', 100);

        skip(200); // past cel
        // create sale of 1k rico for as much risk as it can get
        uint256 back_pre_flow_rico = rico.balanceOf(self);
        uint256 aid = flow.flow(address(rico), WAD * 1000, address(risk), type(uint256).max);
        uint256 back_post_flow_rico = rico.balanceOf(self);
        assertEq(back_pre_flow_rico, back_post_flow_rico + 1000*WAD);
        uint256 pool_rico_0 = rico.balanceOf(rico_risk_pool);
        uint256 back_risk_1 = risk.balanceOf(self);

        // flow glugs once to empty ramps charge
        flow.glug(aid);
        uint256 pool_rico_1 = rico.balanceOf(rico_risk_pool);
        assertEq(pool_rico_1 - pool_rico_0, 100 * rico.totalSupply() / 1000000);
        uint256 back_risk_2 = risk.balanceOf(self);
        assertGt(back_risk_2, back_risk_1 + 80*WAD);  // 80 is some significant portion of 100 but less due to slippage

        // instant repeat should revert (BAL#510, zero amount in)
        vm.expectRevert(UniFlower.ErrSwapFail.selector);
        flow.glug(aid);
        uint256 pool_rico_2 = rico.balanceOf(rico_risk_pool);
        assertEq(pool_rico_1, pool_rico_2);

        // wait half recharge period and half max charge should be swapped
        skip(50);
        flow.glug(aid);
        uint256 pool_rico_3 = rico.balanceOf(rico_risk_pool);
        assertEq(pool_rico_1, pool_rico_3 - 50 * rico.totalSupply() / 1000000);

        assertEq(back_count, 0);
    }

    function test_refund() public {
        flow.curb(address(rico), 'vel', WAD);
        flow.curb(address(rico), 'rel', WAD * 100000);
        flow.curb(address(rico), 'cel', 100);

        // create sale of 1k rico for 200 risk, three glugs should reach want amount
        uint256 back_pre_flow_rico = rico.balanceOf(self);
        uint256 aid = flow.flow(address(rico), WAD * 1000, address(risk), WAD * 200);
        uint256 back_post_flow_rico = rico.balanceOf(self);
        assertEq(back_pre_flow_rico, back_post_flow_rico + 1000*WAD);
        uint256 back_risk_1 = risk.balanceOf(self);

        // complete sale and test flowback gets called exactly once
        flow.glug(aid);
        skip(100);
        flow.glug(aid);
        assertEq(back_count, 0);
        skip(100);
        flow.glug(aid);
        assertEq(back_count, 1);

        uint256 back_risk_2 = risk.balanceOf(self);
        uint256 back_final_rico = rico.balanceOf(self);

        // assert sensible refund quantity
        assertGt(back_final_rico, back_post_flow_rico + 700*WAD);
        // assert back has gained all risk wanted
        assertEq(back_risk_2, back_risk_1 + 200*WAD);

        // further glug attempts with same aid should fail
        skip(100);
        vm.expectRevert(UniFlower.ErrEmptyAid.selector);
        flow.glug(aid);
    }

    function testFail_selling_without_paying() public {
        flow.curb(address(rico), 'vel', WAD);
        flow.curb(address(rico), 'rel', WAD * 100000);
        flow.curb(address(rico), 'cel', 100);
        flow.flow(address(rico), WAD * 1000000, address(risk), type(uint256).max);
    }

    function test_dust() public {
        flow.curb(address(rico), 'vel', WAD);
        flow.curb(address(rico), 'rel', WAD * 100000);
        flow.curb(address(rico), 'cel', 100);
        flow.curb(address(rico), 'del', WAD * 20);

        // create sale of 110 rico for as much risk as it can get
        uint256 back_pre_flow_rico = rico.balanceOf(self);
        uint256 aid = flow.flow(address(rico), WAD * 110, address(risk), type(uint256).max);
        uint256 back_post_flow_rico = rico.balanceOf(self);
        assertEq(back_pre_flow_rico, back_post_flow_rico + 110*WAD);
        uint256 pool_rico_0 = rico.balanceOf(rico_risk_pool);
        uint256 back_risk_1 = risk.balanceOf(self);

        // the sale would leave 10 behind, < del of 20
        // so the entire quantity should get delivered
        flow.glug(aid);
        uint256 pool_rico_1 = rico.balanceOf(rico_risk_pool);
        assertEq(pool_rico_0, pool_rico_1 - 110*WAD);
        uint256 back_risk_2 = risk.balanceOf(self);
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

        skip(1);
        vm.expectRevert(UniFlower.ErrTinyFlow.selector);
        flow.flow(address(rico), WAD * 19, address(risk), type(uint256).max);
        flow.flow(address(rico), WAD * 20, address(risk), type(uint256).max);
    }

    function test_repeat_and_concurrant_sales() public {
    }

    function test_other() public {
    }

    function test_glug_nonreentrant() public {
        Gem hgm = Gem(address(new HackyGem(flow, bytes32('hgm'), bytes32('HGM'))));
        uint amt = 1000 * WAD;

        hgm.mint(self, amt*1000);
        // give hgm a bunch of reserve hgm
        // this test tries to "steal" some reserves
        hgm.mint(address(flow), 100000 * WAD);
        hgm.approve(address(flow), type(uint).max);
        hgm.approve(router, type(uint).max);
        flow.approve_gem(address(hgm));

        rico.mint(self, amt*1000);
        rico.approve(router, type(uint).max);

        rico.mint(address(flow), amt * 7);
        PoolArgs memory rico_hgm_args = getArgs(arico, amt * 5, address(hgm), amt * 5, 3000, x96(1));
        create_and_join_pool(rico_hgm_args);
        uint cel = 10;
        flow.curb(address(hgm), 'vel', amt);
        flow.curb(address(hgm), 'rel', WAD);
        flow.curb(address(hgm), 'bel', block.timestamp);
        flow.curb(address(hgm), 'cel', cel);
        address [] memory a2 = new address[](2);
        uint24  [] memory f1 = new uint24 [](1);
        a2[0] = address(hgm);
        a2[1] = arico;
        f1[0] = 3000;
        (bytes memory f, bytes memory r) = create_path(a2, f1);

        flow.setPath(address(hgm), arico, f, r);
        skip(cel / 2);

        // make wam tiny so first glug is last
        // glug will run twice without reentrancyguard
        uint aid = flow.flow(address(hgm), amt, arico, WAD);
        HackyGem(address(hgm)).setdepth(1);
        assertEq(back_count, 0);
        vm.expectRevert(Lock.ErrLock.selector);
        flow.glug(aid);
    }
}

contract FlowJsTest is Test, RicoSetUp, Flowback {
    uint256 back_count = 0;
    address rico_risk_pool;

    function assertRangeAbs(uint actual, uint expected, uint tolerance) internal {
        assertGe(actual, expected - tolerance);
        assertLe(actual, expected + tolerance);
    }

    function flowback(uint256, uint) external {
        back_count += 1;
    }

    function setUp() public {
        make_bank();
        rico.mint(self, 10000 * WAD);
        risk.mint(self, 10000 * WAD);
        rico.approve(router, type(uint256).max);
        risk.approve(router, type(uint256).max);
        rico.approve(address(flow), type(uint256).max);
        risk.approve(address(flow), type(uint256).max);
        rico_risk_pool = getPoolAddr(arico, arisk, 3000);
        PoolArgs memory rico_risk_args = getArgs(arico, 2000 * WAD, arisk, 2000 * WAD, 3000, x96(1));
        join_pool(rico_risk_args);
    }

    function test_rate_limiting_flap_absolute_rate() public {
        flow.curb(arico, 'vel', WAD / 10);
        flow.curb(arico, 'rel', 1000 * WAD);
        flow.curb(arico, 'bel', 0);
        flow.curb(arico, 'cel', 1000);
        uint256 pool_rico_0 = rico.balanceOf(rico_risk_pool);
        // consume half the allowance
        uint256 aid = flow.flow(arico, 50 * WAD, arisk, UINT256_MAX);
        flow.glug(aid);

        uint256 pool_rico_1 = rico.balanceOf(rico_risk_pool);
        // recharge by a quarter of capacity so should sell 75%
        skip(250);

        aid = flow.flow(arico, 100 * WAD, arisk, UINT256_MAX);
        flow.glug(aid);

        uint256 pool_rico_2 = rico.balanceOf(rico_risk_pool);

        uint sale0 = pool_rico_1 - pool_rico_0;
        uint sale1 = pool_rico_2 - pool_rico_1;
        assertRangeAbs(sale0, 50 * WAD, WAD / 2);
        assertRangeAbs(sale1, 75* WAD, WAD * 3 / 5);
    }

    function test_rate_limiting_flap_relative_rate() public {
        flow.curb(arico, 'vel', 10000 * WAD);
        flow.curb(arico, 'rel', WAD / 100000);
        flow.curb(arico, 'bel', 0);
        flow.curb(arico, 'cel', 1000);

        uint256 pool_rico_0 = rico.balanceOf(rico_risk_pool);
        // consume half the allowance
        uint256 aid = flow.flow(arico, 50 * WAD, arisk, UINT256_MAX);
        flow.glug(aid);

        uint256 pool_rico_1 = rico.balanceOf(rico_risk_pool);
        skip(250);

        aid = flow.flow(arico, 100 * WAD, arisk, UINT256_MAX);
        flow.glug(aid);

        uint256 pool_rico_2 = rico.balanceOf(rico_risk_pool);

        uint sale0 = pool_rico_1 - pool_rico_0;
        uint sale1 = pool_rico_2 - pool_rico_1;
        assertRangeAbs(sale0, 50 * WAD, WAD / 2);
        assertRangeAbs(sale1, 75 * WAD, WAD * 3 / 5);
    }
}

contract OverrideableGem {
    bytes32 public name;
    bytes32 public symbol;
    uint256 public totalSupply;
    uint8   public constant decimals = 18;

    mapping (address => uint)                      public balanceOf;
    mapping (address => mapping (address => uint)) public allowance;
    mapping (address => uint)                      public nonces;
    mapping (address => bool)                      public wards;

    bytes32 immutable DOMAIN_SUBHASH = keccak256(
        'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'
    );
    bytes32 immutable PERMIT_TYPEHASH = keccak256(
        'Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)'
    );

    event Approval(address indexed src, address indexed usr, uint256 wad);
    event Transfer(address indexed src, address indexed dst, uint256 wad);
    event Mint(address indexed caller, address indexed user, uint256 wad);
    event Burn(address indexed caller, address indexed user, uint256 wad);
    event Ward(address indexed setter, address indexed user, bool authed);

    error ErrPermitDeadline();
    error ErrPermitSignature();
    error ErrOverflow();
    error ErrUnderflow();
    error ErrWard();

    constructor(bytes32 name_, bytes32 symbol_)
      payable
    {
        name = name_;
        symbol = symbol_;

        wards[msg.sender] = true;
        emit Ward(msg.sender, msg.sender, true);
    }

    function ward(address usr, bool authed)
      payable external {
        if (!wards[msg.sender]) revert ErrWard();
        wards[usr] = authed;
        emit Ward(msg.sender, usr, authed);
    }

    function mint(address usr, uint wad)
      payable external {
        if (!wards[msg.sender]) revert ErrWard();
        // only need to check totalSupply for overflow
        unchecked {
            uint256 prev = totalSupply;
            if (prev + wad < prev) {
                revert ErrOverflow();
            }
            balanceOf[usr] += wad;
            totalSupply     = prev + wad;
            emit Mint(msg.sender, usr, wad);
        }
    }

    function burn(address usr, uint wad)
      payable external {
        if (!wards[msg.sender]) revert ErrWard();
        // only need to check balanceOf[usr] for underflow
        unchecked {
            uint256 prev = balanceOf[usr];
            balanceOf[usr] = prev - wad;
            totalSupply    -= wad;
            emit Burn(msg.sender, usr, wad);
            if (prev < wad) {
                revert ErrUnderflow();
            }
        }
    }

    function transfer(address dst, uint wad)
      payable external virtual returns (bool ok)
    {
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

    function transferFrom(address src, address dst, uint wad)
      payable external returns (bool ok)
    {
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

    function approve(address usr, uint wad)
      payable external returns (bool ok)
    {
        ok = true;
        allowance[msg.sender][usr] = wad;
        emit Approval(msg.sender, usr, wad);
    }

    // EIP-2612
    function permit(address owner, address spender, uint256 value, uint256 deadline,
                    uint8 v, bytes32 r, bytes32 s)
      payable external {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
        address signer;
        unchecked {
            signer = ecrecover(
                keccak256(abi.encodePacked( "\x19\x01",
                    keccak256(abi.encode( DOMAIN_SUBHASH,
                        keccak256("GemPermit"), keccak256("0"),
                        block.chainid, address(this))),
                    keccak256(abi.encode( PERMIT_TYPEHASH, owner, spender,
                        value, nonces[owner]++, deadline )))),
                v, r, s
            );
        }
        if (signer == address(0)) { revert ErrPermitSignature(); }
        if (owner != signer) { revert ErrPermitSignature(); }
        if (block.timestamp > deadline) { revert ErrPermitDeadline(); }
    }
}

contract HackyGem is OverrideableGem {
    UniFlower flow;
    uint depth;

    constructor(UniFlower _flow, bytes32 name, bytes32 symbol) OverrideableGem(name, symbol) {
        flow = _flow;
    }

    function setdepth(uint _depth) public {
        depth = _depth;
    }

    function transfer(address dst, uint wad) public payable virtual override returns (bool ok) {
        if (depth > 0) {
            depth--;
            flow.glug(flow.count());
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
