// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.25;
import 'forge-std/Test.sol';

import '../src/mixin/math.sol';
import { Block } from '../lib/feedbase/src/mixin/Read.sol';
import { IUniWrapper } from '../lib/feedbase/src/adapters/UniswapV3Adapter.sol';
import { ParAdapter } from "../lib/feedbase/src/adapters/ParAdapter.sol";
import { Feedbase } from '../lib/feedbase/src/Feedbase.sol';
import { Gem, GemFab } from '../lib/gemfab/src/gem.sol';
import { Bank } from '../src/bank.sol';
import { BaseHelper, BankDiamond, WethLike } from './BaseHelper.sol';
import { 
    Ball, File, Vat, Vow, Vox, Multiplier, Divider, ChainlinkAdapter, UniswapV3Adapter
} from '../src/ball.sol';

contract Guy {
    address payable bank;

    constructor(address payable _bank) {
        bank = _bank;
    }
    function approve(address gem, address dst, uint amt) public {
        Gem(gem).approve(dst, amt);
    }
    function frob(bytes32 ilk, address usr, int dink, int dart) public {
        Vat(bank).frob(ilk, usr, dink, dart);
    }
    function transfer(address gem, address dst, uint amt) public {
        Gem(gem).transfer(dst, amt);
    }
    function bail(bytes32 i, address u) public returns (uint) {
        return Vat(bank).bail(i, u);
    }
    function keep(bytes32[] calldata ilks) public {
        Vow(bank).keep(ilks);
    }
}

abstract contract RicoSetUp is BaseHelper {
    bytes32 constant public dilk  = "dai";
    bytes32 constant public gilk  = "gold";
    bytes32 constant public dutag = "dai:usd";
    bytes32 constant public grtag = "gold:ref";
    bytes32 constant public wrtag = "weth:ref";
    bytes32 constant public drtag = "dai:ref";
    bytes32 constant public rutag = "rico:usd";
    uint160 constant public risk_price = X96;
    uint256 constant public INIT_PAR   = RAY;
    uint256 constant public init_mint  = 10000;
    uint256 constant public FEED_LOOKAHEAD = 1000;
    uint256 constant public FEE_2X_ANN = uint(1000000021964508944519921664);
    uint256 constant public FEE_1_5X_ANN = uint(1000000012848414058163994624);
    address constant public fsrc = 0xF33df33dF33dF33df33df33df33dF33DF33Df33D;

    Ball       public ball;
    Divider    public divider;
    Multiplier public multiplier;
    UniswapV3Adapter public uniadapter;
    ChainlinkAdapter public cladapter;
    ParAdapter public paradapter;
    Feedbase   public feed;
    Gem        public dai;
    Gem        public gold;
    Gem        public rico;
    Gem        public risk;
    GemFab     public gemfab;
    address    public ricodai;
    address    public arico;
    address    public arisk;
    address    public agold;
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
        _bob.frob(gilk, address(_bob), int(amt), int(amt));
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

    // helpers for feeds, so we don't have to deal with feed's structure
    function feedpull(bytes32 tag) internal view returns (bytes32, uint) {
        return feed.pull(fsrc, tag);
    }

    function feedpush(bytes32 tag, bytes32 val, uint ttl) internal {
        vm.prank(fsrc);
        feed.push(tag, val, ttl);
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

        uniadapter = new UniswapV3Adapter(IUniWrapper(uniwrapper));
        divider    = new Divider(address(feed));
        multiplier = new Multiplier(address(feed));
        cladapter  = new ChainlinkAdapter();
        paradapter = new ParAdapter(bank);

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
            20000 // ttl
        );

        address[] memory unigems = new address[](2);
        (unigems[0], unigems[1]) = (WETH, DAI);
        address[] memory unisrcs = new address[](2);
        (unisrcs[0], unisrcs[1]) = (fsrc, fsrc);
        bytes32[] memory unitags = new bytes32[](2);
        (unitags[0], unitags[1]) = (WETH_REF_TAG, DAI_REF_TAG);
        uint256[] memory uniliqrs = new uint[](2);
        (uniliqrs[0], uniliqrs[1]) = (RAY, RAY);

        Ball.BallArgs memory bargs = Ball.BallArgs(
            bank,
            address(feed),
            address(uniadapter),
            address(divider),
            address(multiplier),
            address(cladapter),
            arico,
            arisk,
            ricodai,
            DAI,
            DAI_USD_AGG,
            XAU_USD_AGG,
            INIT_PAR,
            100000 * WAD,
            20000, // ricodai
            BANKYEAR / 4,
            BANKYEAR, // daiusd
            BANKYEAR, // xauusd
            Bank.Ramp(block.timestamp, 1, RAY / BLN, RAY)
        );

        ball = new Ball(bargs);

        BankDiamond(bank).transferOwnership(address(ball));
        uniadapter.ward(address(ball), true);
        divider.ward(address(ball), true);
        multiplier.ward(address(ball), true);
        cladapter.ward(address(ball), true);

        ball.setup(bargs);
        ball.makeilk(ips[0]);
        ball.approve(self);
        BankDiamond(bank).acceptOwnership();

        ////////// these are outside ball, but must be part of real deploy process, unless warding ball first w create2
        Gem(rico).ward(bank, true);
        Gem(risk).ward(bank, true);
        //////////

        File(bank).file('tip.src', bytes32(bytes20(fsrc)));
        Vat(bank).filk(WETH_ILK, 'src', bytes32(bytes20(fsrc)));

        feedpush(RISK_RICO_TAG, bytes32(RAY), block.timestamp + FEED_LOOKAHEAD);
        feedpush(RICO_RISK_TAG, bytes32(RAY), block.timestamp + FEED_LOOKAHEAD);
    }

    function init_erc20_ilk(bytes32 ilk, address gem, bytes32 tag) public {
        Gem(gem).approve(bank, type(uint256).max);
        Vat(bank).init(ilk, gem);
        Vat(bank).filk(ilk, 'src',  bytes32(bytes20(fsrc)));
        Vat(bank).filk(ilk, 'tag',  tag);
        Vat(bank).filk(ilk, 'liqr', bytes32(RAY));
        Vat(bank).filk(ilk, 'pep',  bytes32(uint(2)));
        Vat(bank).filk(ilk, 'pop',  bytes32(RAY));
        Vat(bank).filk(ilk, 'chop', bytes32(RAY));
        Vat(bank).filk(ilk, 'line', bytes32(init_mint * 10 * RAD));
        Vat(bank).filk(ilk, 'fee',  bytes32(uint(1000000001546067052200000000)));  // 5%
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

    function check_integrity() internal view {
        uint sup  = rico.totalSupply();
        uint joy  = Vat(bank).joy();
        uint sin  = Vat(bank).sin();
        uint debt = Vat(bank).debt();
        uint rest = Vat(bank).rest();
        uint tart = Vat(bank).ilks(gilk).tart;
        uint rack = Vat(bank).ilks(gilk).rack;

        assertEq(rico.balanceOf(bank), 0);
        assertEq(joy + sup, debt);
        assertEq(tart * rack + sin, (sup + joy) * RAY + rest);
    }

    modifier _check_integrity_after_ {
        _;
        check_integrity();
    }

}
