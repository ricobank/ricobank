// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.19;
import 'forge-std/Test.sol';

import '../src/mixin/math.sol';
import { Feedbase } from '../lib/feedbase/src/Feedbase.sol';
import { Block } from '../lib/feedbase/src/mixin/Read.sol';
import { Divider } from '../lib/feedbase/src/combinators/Divider.sol';
import { Multiplier } from '../lib/feedbase/src/combinators/Multiplier.sol';
import { Medianizer } from '../lib/feedbase/src/Medianizer.sol';
import { GemFab, Gem } from '../lib/gemfab/src/gem.sol';
import { Ball } from '../src/ball.sol';
import { Vat } from '../src/vat.sol';
import { Vow } from '../src/vow.sol';
import { Vox } from '../src/vox.sol';
import { ERC20Hook } from '../src/hook/ERC20hook.sol';
import { UniNFTHook } from '../src/hook/nfpm/UniV3NFTHook.sol';
import { BaseHelper, WethLike } from './BaseHelper.sol';
import { Bank } from '../src/bank.sol';
import { File } from '../src/file.sol';
import { BankDiamond } from '../src/diamond.sol';

contract Guy {
    address payable bank;

    constructor(address payable _bank) {
        bank = _bank;
    }
    function approve(address gem, address dst, uint amt) public {
        Gem(gem).approve(dst, amt);
    }
    function frob(bytes32 ilk, address usr, bytes calldata dink, int dart) public {
        Vat(bank).frob(ilk, usr, dink, dart);
    }
    function transfer(address gem, address dst, uint amt) public {
        Gem(gem).transfer(dst, amt);
    }
    function bail(bytes32 i, address u) public returns (bytes memory) {
        return Vat(bank).bail(i, u);
    }
    function keep(bytes32[] calldata ilks) public {
        Vow(bank).keep(ilks);
    }
}

abstract contract RicoSetUp is BaseHelper {
    bytes32 constant public dilk  = "dai";
    bytes32 constant public gilk  = "gold";
    bytes32 constant public rilk  = "ruby";
    bytes32 constant public uilk  = ":uninft";
    bytes32 constant public dutag = "dai:usd";
    bytes32 constant public grtag = "gold:ref";
    bytes32 constant public wrtag = "weth:ref";
    bytes32 constant public drtag = "dai:ref";

    bytes32 constant public rtag       = "rico:usd";
    uint160 constant public risk_price = 2 ** 96;
    uint256 constant public INIT_PAR   = RAY;
    uint256 constant public init_mint  = 10000;
    uint256 constant public no_rush    = RAY;
    uint256 constant public flappep    = RAY;
    uint256 constant public flappop    = RAY;
    uint256 constant public floppep    = RAY;
    uint256 constant public floppop    = RAY;
    address public immutable self = payable(address(this));

    ERC20Hook  public hook;
    UniNFTHook public nfthook;
    Medianizer public mdn;
    Ball       public ball;
    Divider    public divider;
    Multiplier public multiplier;
    Feedbase   public feed;
    Gem        public dai;
    Gem        public gold;
    Gem        public ruby;
    Gem        public rico;
    Gem        public risk;
    GemFab     public gemfab;
    address    public ricodai;
    address    public ricorisk;
    address    public arico;
    address    public arisk;
    address    public agold;
    address    public aruby;
    address    payable public ahook;
    address    public uniwrapper;

    Guy _bob;
    Guy guy;

    function rico_mint(uint amt, bool bail) internal {
        uint start_gold = gold.balanceOf(self);
        _bob = new Guy(bank);
        (bytes32 v, uint t) = feedpull(grtag);
        feedpush(grtag, bytes32(RAY * 10000), type(uint).max);
        gold.mint(address(_bob), amt);
        _bob.approve(agold, bank, amt);
        _bob.frob(gilk, address(_bob), abi.encodePacked(amt), int(amt));
        feedpush(grtag, bytes32(0), type(uint).max);
        if (bail) Vat(bank).bail(gilk, address(_bob));
        _bob.transfer(arico, self, amt);
        feedpush(grtag, v, t);
        uint end_gold = gold.balanceOf(self);
        gold.burn(self, end_gold - start_gold);
    }

    function force_fees(uint gain) public {
        // Create imaginary fees, add to debt and joy
        // Avoid manipulating vat like this usually
        uint256 debt_0   = Vat(bank).debt();
        uint256 joy_0    = Vat(bank).joy();

        uint256 joy_idx  = 2;
        uint256 debt_idx = 5;
        bytes32 vat_info = 'vat.0';
        bytes32 vat_pos  = keccak256(abi.encodePacked(vat_info));
        bytes32 joy_pos  = bytes32(uint(vat_pos) + joy_idx);
        bytes32 debt_pos = bytes32(uint(vat_pos) + debt_idx);

        vm.store(bank, joy_pos,  bytes32(joy_0  + gain));
        vm.store(bank, debt_pos, bytes32(debt_0 + gain));
    }

    function _art(bytes32 ilk, address usr) internal view returns (uint art) {
        art = Vat(bank).urns(ilk, usr);
    }

    function check_gas(uint gas, uint expectedgas) internal view {
        /* // not used anymore
        uint usedgas = gas - gasleft();
        if (usedgas < expectedgas) {
            console.log("saved %s gas...currently %s", expectedgas - usedgas, usedgas);
        }
        if (usedgas > expectedgas) {
            console.log("gas increase by %s...currently %s", usedgas - expectedgas, usedgas);
        }
       */
    }

    function feedpull(bytes32 tag) internal view returns (bytes32, uint) {
        return feed.pull(address(mdn), tag);
    }

    function feedpush(bytes32 tag, bytes32 val, uint ttl) internal {
        feed.push(tag, val, ttl);
        mdn.poke(tag);
    }

    function make_feed(bytes32 tag) internal {
        address[] memory sources = new address[](2);
        bytes32[] memory tags    = new bytes32[](2);
        uint256[] memory scales  = new uint256[](2);
        sources[0] = address(this); tags[0] = bytes32(tag);   scales[0] = RAY;
        sources[1] = address(this); tags[1] = bytes32("ONE"); scales[1] = RAY;
        divider.setConfig(tag, Block.Config(sources, tags));
        // todo quorum?
        Medianizer.Config memory mdnconf =
            Medianizer.Config(new address[](1), new bytes32[](1), 0);
        mdnconf.srcs[0] = address(divider);
        mdnconf.tags[0] = tag;
        mdn.setConfig(tag, mdnconf);
    }

    function make_bank() public {
        feed   = new Feedbase();
        gemfab = new GemFab();
        rico  = gemfab.build(bytes32("Rico"), bytes32("RICO"));
        risk  = gemfab.build(bytes32("Rico Riskshare"), bytes32("RISK"));
        arico = address(rico);
        arisk = address(risk);
        uint160 sqrt_ratio_x96 = get_rico_sqrtx96(INIT_PAR);
        ricodai  = create_pool(arico, DAI,   RICO_FEE, sqrt_ratio_x96);
        ricorisk = create_pool(arico, arisk, RISK_FEE, risk_price);

        uniwrapper = make_uniwrapper();
        bank = make_diamond();

        Ball.IlkParams[] memory ips = new Ball.IlkParams[](1);
        ips[0] = Ball.IlkParams(
            'weth',
            WETH,
            address(0),
            WETH_USD_AGG,
            RAY, // chop
            RAD / 10, // dust
            1000000001546067052200000000, // fee
            100000 * RAD, // line
            RAY, // liqr
            20000, // ttl
            BANKYEAR / 4 // range
        );
        Ball.UniParams memory ups = Ball.UniParams(
            NFPM,
            ':uninft',
            1000000001546067052200000000,
            RAY,
            HOOK_ROOM,
            uniwrapper
        );
        Ball.BallArgs memory bargs = Ball.BallArgs(
            bank,
            address(feed),
            arico,
            arisk,
            ricodai,
            ricorisk,
            router,
            uniwrapper,
            INIT_PAR,
            100000 * WAD,
            20000, // ricodai
            BANKYEAR / 4,
            BANKYEAR, // daiusd
            BANKYEAR, // xauusd
            flappep,
            flappop,
            floppep,
            floppop,
            Bank.Ramp(WAD, WAD, block.timestamp, 1),
            DAI,
            DAI_USD_AGG,
            XAU_USD_AGG
        );

        ball = new Ball(bargs);
        BankDiamond(bank).transferOwnership(address(ball));
        ball.setup(bargs);
        ball.makeilk(ips[0]);
        ball.makeuni(ups);
        ball.approve(self);
        BankDiamond(bank).acceptOwnership();


        ////////// these are outside ball, but must be part of real deploy process, unless warding ball first w create2
        Gem(rico).ward(bank, true);
        Gem(risk).ward(bank, true);
        // Gem(rico).ward(address(self), false);
        // Gem(risk).ward(address(self), false);
        //////////

        hook = ball.hook();
        nfthook = ball.nfthook();
        mdn  = ball.mdn();
        divider = ball.divider();

        ahook = payable(address(hook));

        feed.push(bytes32("ONE"), bytes32(RAY), type(uint).max);
        make_feed(rtag);
        make_feed(wrtag);
        make_feed(grtag);
        make_feed(RISK_RICO_TAG);
        make_feed(RICO_RISK_TAG);

        feedpush(RISK_RICO_TAG, bytes32(RAY), block.timestamp + 1000);
        feedpush(RICO_RISK_TAG, bytes32(RAY), block.timestamp + 1000);
    }

    function init_dai() public {
        dai = Gem(DAI);
        vm.prank(VAULT);
        dai.transfer(address(this), 10000 * WAD);
        dai.approve(bank, type(uint256).max);
        Vat(bank).init(dilk, address(hook));
        Vat(bank).filhi(dilk, 'gem', dilk, bytes32(bytes20(address(dai))));
        Vat(bank).filhi(dilk, 'fsrc', dilk, bytes32(bytes20(self)));
        Vat(bank).filhi(dilk, 'ftag', dilk, drtag);
        Vat(bank).filk(dilk, 'hook', bytes32(uint(bytes32(bytes20(address(hook))))));
        Vat(bank).filk(dilk, bytes32('chop'), bytes32(RAD));
        Vat(bank).filk(dilk, bytes32('line'), bytes32(init_mint * 10 * RAD));
        Vat(bank).filk(dilk, bytes32('fee'), bytes32(uint(1000000001546067052200000000)));  // 5%
        // feedpush(dutag, bytes32(RAY), block.timestamp + 1000);
        make_feed(drtag);
    }

    function init_gold() public {
        gold = Gem(address(gemfab.build(bytes32("Gold"), bytes32("GOLD"))));
        gold.mint(self, init_mint * WAD);
        gold.approve(bank, type(uint256).max);
        Vat(bank).init(gilk, address(hook));
        Vat(bank).filhi(gilk, 'gem', gilk, bytes32(bytes20(address(gold))));
        Vat(bank).filhi(gilk, 'fsrc', gilk, bytes32(bytes20(self)));
        Vat(bank).filhi(gilk, 'ftag', gilk, grtag);
 
        Vat(bank).filk(gilk, 'hook', bytes32(uint(bytes32(bytes20(address(hook))))));
        // todo fix other chops, should be rays
        Vat(bank).filk(gilk, bytes32('chop'), bytes32(RAY));
        Vat(bank).filk(gilk, bytes32('line'), bytes32(init_mint * 10 * RAD));
        Vat(bank).filk(gilk, bytes32('fee'), bytes32(uint(1000000001546067052200000000)));  // 5%
        feedpush(grtag, bytes32(RAY), block.timestamp + 1000);
        agold = address(gold);
    }

    function init_ruby() public {
        ruby = Gem(address(gemfab.build(bytes32("Ruby"), bytes32("RUBY"))));
        ruby.mint(self, init_mint * WAD);
        ruby.approve(bank, type(uint256).max);
        Vat(bank).init(rilk, address(hook));
        Vat(bank).filhi(rilk, 'gem', rilk, bytes32(bytes20(address(ruby))));
        Vat(bank).filhi(rilk, 'fsrc', rilk, bytes32(bytes20(self)));
        Vat(bank).filhi(rilk, 'ftag', rilk, rtag);
 
        Vat(bank).filk(rilk, 'hook', bytes32(uint(bytes32(bytes20(address(hook))))));
        Vat(bank).filk(rilk, bytes32('chop'), bytes32(RAD));
        Vat(bank).filk(rilk, bytes32('line'), bytes32(init_mint * 10 * RAD));
        Vat(bank).filk(rilk, bytes32('fee'), bytes32(uint(1000000001546067052200000000)));  // 5%
        feedpush(rtag, bytes32(RAY), block.timestamp + 1000);
        aruby = address(ruby);
    }

    function prepguyrico(uint amt, bool bail) internal {
        rico_mint(amt, bail);
        rico.transfer(address(guy), amt);
    }
}
