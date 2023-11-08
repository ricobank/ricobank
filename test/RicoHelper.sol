// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.19;
import 'forge-std/Test.sol';

import '../src/mixin/math.sol';
import { Block } from '../lib/feedbase/src/mixin/Read.sol';
import { Gem, GemFab } from '../lib/gemfab/src/gem.sol';
import { Bank } from '../src/bank.sol';
import { BaseHelper, BankDiamond, WethLike } from './BaseHelper.sol';
import { 
    Ball, File, Vat, Vow, Vox, ERC20Hook, Medianizer, Multiplier,
    Divider, Feedbase
} from '../src/ball.sol';
import { Hook } from '../src/hook/hook.sol';

import { UniNFTHook } from '../src/hook/nfpm/UniV3NFTHook.sol';

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

// pretty normal single-uint frobhook
contract FrobHook is Hook {
    function frobhook(FHParams calldata p) external payable returns (bool) {
        // safer when dink >= 0 and dart <= 0
        return int(uint(bytes32(p.dink[:32]))) >= 0 && p.dart <= 0;
    }
    function bailhook(BHParams calldata) external payable returns (bytes memory) {}
    function safehook(
        bytes32, address
    ) pure external returns (uint, uint, uint) {
        // (1, 1, uint_max)
        return(10 ** 45, 10 ** 45, type(uint256).max);
    }
    function ink(bytes32, address) external pure returns (bytes memory) {
        return abi.encode(uint(0));
    }
}

// doesn't really do anything, always returns 0 or false
contract ZeroHook is Hook {
    function frobhook(FHParams calldata) external payable returns (bool) {}
    function bailhook(BHParams calldata) external payable returns (bytes memory) {}
    function safehook(
        bytes32, address
    ) pure external returns (uint, uint, uint){
        return(0, 0, type(uint256).max); // (almost) always unsafe
    }
    function ink(bytes32, address) external pure returns (bytes memory) {
        return abi.encode(uint(0));
    }
}

abstract contract RicoSetUp is BaseHelper {
    bytes32 constant public dilk  = "dai";
    bytes32 constant public gilk  = "gold";
    bytes32 constant public uilk  = ":uninft";
    bytes32 constant public dutag = "dai:usd";
    bytes32 constant public grtag = "gold:ref";
    bytes32 constant public wrtag = "weth:ref";
    bytes32 constant public drtag = "dai:ref";
    bytes32 constant public rrtag = "rico:usd";
    uint160 constant public risk_price = 2 ** 96;
    uint256 constant public INIT_PAR   = RAY;
    uint256 constant public init_mint  = 10000;
    uint256 constant public platpep    = 2;
    uint256 constant public platpop    = RAY;
    uint256 constant public plotpep    = 2;
    uint256 constant public plotpop    = RAY;
    uint256 constant public FEED_LOOKAHEAD = 1000;

    ERC20Hook  public hook;
    UniNFTHook public nfthook;
    Medianizer public mdn;
    Ball       public ball;
    Divider    public divider;
    Multiplier public multiplier;
    Feedbase   public feed;
    Gem        public dai;
    Gem        public gold;
    Gem        public rico;
    Gem        public risk;
    GemFab     public gemfab;
    address    public ricodai;
    address    public ricorisk;
    address    public arico;
    address    public arisk;
    address    public agold;
    address    payable public ahook;
    address    public uniwrapper;


    Guy _bob;
    Guy guy;

    // mint some gold to a fake account to frob some rico
    function rico_mint(uint amt, bool bail) internal {
        uint start_gold = gold.balanceOf(self);

        // create fake account and mint some gold to it
        _bob = new Guy(bank);
        gold.mint(address(_bob), amt);
        _bob.approve(agold, bank, amt);

        // save last gold feed and temporarily set it high
        (bytes32 v, uint t) = feedpull(grtag);
        feedpush(grtag, bytes32(RAY * 10000), type(uint).max);

        // bob borrows the rico and sends back to self
        _bob.frob(gilk, address(_bob), abi.encodePacked(amt), int(amt));
        _bob.transfer(arico, self, amt);

        if (bail) {
            // set feed to 0 and liquidate
            feedpush(grtag, bytes32(0), type(uint).max);
            Vat(bank).bail(gilk, address(_bob));
        }

        // restore gold feed and previous gold supply
        feedpush(grtag, v, t);
        gold.burn(self, gold.balanceOf(self) - start_gold);
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

    function force_sin(uint val) public {
        // set sin as if it was covered by a good bail
        uint256 sin_idx  = 3;
        bytes32 vat_info = 'vat.0';
        bytes32 vat_pos  = keccak256(abi.encodePacked(vat_info));
        bytes32 sin_pos  = bytes32(uint(vat_pos) + sin_idx);

        vm.store(bank, sin_pos, bytes32(val));
    }

    function _art(bytes32 ilk, address usr) internal view returns (uint art) {
        art = Vat(bank).urns(ilk, usr);
    }

    // helpers for feeds, so we don't have to deal with mdn all the time
    function feedpull(bytes32 tag) internal view returns (bytes32, uint) {
        return feed.pull(address(mdn), tag);
    }

    function feedpush(bytes32 tag, bytes32 val, uint ttl) internal {
        feed.push(tag, val, ttl);
        mdn.poke(tag);
    }

    // create a new feed that's just feed(mdn, tag) == feed(self, tag)
    function make_feed(bytes32 tag) internal {
        feed.push(bytes32("ONE"), bytes32(RAY), type(uint).max);
        address[] memory sources = new address[](2);
        bytes32[] memory tags    = new bytes32[](2);
        uint256[] memory scales  = new uint256[](2);
        sources[0] = address(this); tags[0] = bytes32(tag);   scales[0] = RAY;
        sources[1] = address(this); tags[1] = bytes32("ONE"); scales[1] = RAY;
        divider.setConfig(tag, Block.Config(sources, tags));
        // todo quorum?
        Medianizer.Config memory mdnconf =
            Medianizer.Config(new address[](1), new bytes32[](1), 1);
        mdnconf.srcs[0] = address(divider);
        mdnconf.tags[0] = tag;
        mdn.setConfig(tag, mdnconf);
    }

    function make_bank() public {
        feed   = new Feedbase();
        gemfab = new GemFab();
        rico   = gemfab.build(bytes32("Rico"), bytes32("RICO"));
        risk   = gemfab.build(bytes32("Rico Riskshare"), bytes32("RISK"));
        arico  = address(rico);
        arisk  = address(risk);

        uniwrapper = make_uniwrapper();
        bank       = make_diamond();

        // deploy bank with one ERC20 ilk and one NFPM ilk
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
            uniwrapper,
            DAI,
            DAI_USD_AGG,
            XAU_USD_AGG,
            INIT_PAR,
            100000 * WAD,
            20000, // ricodai
            BANKYEAR / 4,
            BANKYEAR, // daiusd
            BANKYEAR, // xauusd
            platpep,
            platpop,
            plotpep,
            plotpop,
            Bank.Ramp(WAD / BLN, block.timestamp, 1, WAD)
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
        //////////

        hook    = ball.hook();
        nfthook = ball.nfthook();
        mdn     = ball.mdn();
        divider = ball.divider();
        ahook   = payable(address(hook));

        make_feed(rrtag);
        make_feed(wrtag);
        make_feed(grtag);
        make_feed(drtag);
        make_feed(RISK_RICO_TAG);
        make_feed(RICO_RISK_TAG);
        feedpush(RISK_RICO_TAG, bytes32(RAY), block.timestamp + FEED_LOOKAHEAD);
        feedpush(RICO_RISK_TAG, bytes32(RAY), block.timestamp + FEED_LOOKAHEAD);
    }

    function init_erc20_ilk(bytes32 ilk, address gem, bytes32 tag) public {
        Gem(gem).approve(bank, type(uint256).max);
        Vat(bank).init(ilk, address(hook));
        Vat(bank).filh(ilk, 'gem', empty, bytes32(bytes20(gem)));
        Vat(bank).filh(ilk, 'src', empty, bytes32(bytes20(self)));
        Vat(bank).filh(ilk, 'tag', empty, tag);
        Vat(bank).filh(ilk, 'liqr', empty, bytes32(RAY));
        Vat(bank).filh(ilk, 'pep', empty, bytes32(uint(2)));
        Vat(bank).filh(ilk, 'pop', empty, bytes32(RAY));
        Vat(bank).filk(ilk, 'hook', bytes32(uint(bytes32(bytes20(address(hook))))));
        Vat(bank).filk(ilk, 'chop', bytes32(RAY));
        Vat(bank).filk(ilk, 'line', bytes32(init_mint * 10 * RAD));
        Vat(bank).filk(ilk, 'fee', bytes32(uint(1000000001546067052200000000)));  // 5%
        feedpush(tag, bytes32(RAY), block.timestamp + FEED_LOOKAHEAD);
    }

    function init_dai() public {
        dai = Gem(DAI);
        vm.prank(VAULT);
        dai.transfer(address(this), 10000 * WAD);
        init_erc20_ilk(dilk, DAI, drtag);
    }

    function init_gold() public {
        gold = Gem(address(gemfab.build(bytes32("Gold"), bytes32("GOLD"))));
        gold.mint(self, init_mint * WAD);
        agold = address(gold);
        init_erc20_ilk(gilk, agold, grtag);
    }

    // mint some new rico and give it to guy
    function prepguyrico(uint amt, bool bail) internal {
        rico_mint(amt, bail);
        rico.transfer(address(guy), amt);
    }

    function check_integrity() internal {
        uint sup  = rico.totalSupply();
        uint joy  = Vat(bank).joy();
        uint sin  = Vat(bank).sin() / RAY;
        uint debt = Vat(bank).debt();
        uint tart = Vat(bank).ilks(gilk).tart;
        uint rack = Vat(bank).ilks(gilk).rack;

        assertEq(rico.balanceOf(bank), 0);
        assertEq(joy + sup, debt);
        assertEq(rmul(tart, rack), sup + joy - sin);
    }

    modifier _check_integrity_after_ {
        _;
        check_integrity();
    }

}
