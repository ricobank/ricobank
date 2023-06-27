// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.19;
import 'forge-std/Test.sol';

import '../src/mixin/math.sol';
import { Feedbase } from '../lib/feedbase/src/Feedbase.sol';
import { Divider } from '../lib/feedbase/src/combinators/Divider.sol';
import { Medianizer } from '../lib/feedbase/src/Medianizer.sol';
import { GemFab, Gem } from '../lib/gemfab/src/gem.sol';
import { Ball } from '../src/ball.sol';
import { Vat } from '../src/vat.sol';
import { Vow } from '../src/vow.sol';
import { Vox } from '../src/vox.sol';
import { ERC20Hook } from '../src/hook/ERC20hook.sol';
import { UniNFTHook } from '../src/hook/nfpm/UniV3NFTHook.sol';
import { UniSetUp } from "./UniHelper.sol";
import { Bank } from '../src/bank.sol';
import { File } from '../src/file.sol';
import { BankDiamond } from '../src/diamond.sol';

interface WethLike {
    function deposit() external payable;
    function approve(address, uint) external;
    function allowance(address, address) external returns (uint);
    function balanceOf(address) external returns (uint);
}

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
        return Vow(bank).bail(i, u);
    }
    function keep(bytes32[] calldata ilks) public {
        Vow(bank).keep(ilks);
    }
}

abstract contract RicoSetUp is UniSetUp, Math, Test {
    address constant public DAI  = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant public WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant public WETH_USD_AGG  = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    bytes32 constant public WETH_RICO_TAG = "weth:rico";
    bytes32 constant public RICO_RISK_TAG = "rico:risk";
    bytes32 constant public RISK_RICO_TAG = "risk:rico";

    address constant public VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    bytes32 constant public dilk  = "dai";
    bytes32 constant public gilk  = "gold";
    bytes32 constant public wilk  = "weth";
    bytes32 constant public rilk  = "ruby";
    bytes32 constant public uilk  = ":uninft";
    bytes32 constant public dutag = "dai:usd";
    bytes32 constant public grtag = "gold:rico";
    bytes32 constant public wrtag = "weth:rico";
    bytes32 constant public drtag = "dai:rico";

    bytes32 constant public rtag       = "rico:usd";
    uint160 constant public risk_price = 2 ** 96;
    uint24  constant public RICO_FEE   = 500;
    uint24  constant public RISK_FEE   = 3000;
    uint256 constant public HOOK_ROOM  = 8;
    uint256 constant public init_mint  = 10000;
    uint256 constant public BANKYEAR   = (365 * 24 + 6) * 3600;
    uint256 constant public no_rush    = RAY;
    uint256 constant public flappep    = RAY;
    uint256 constant public flappop    = RAY;
    uint256 constant public floppep    = RAY;
    uint256 constant public floppop    = RAY;
    address public immutable azero     = address(0);
    address public immutable self = payable(address(this));

    ERC20Hook   public hook;
    UniNFTHook  public nfthook;
    Medianizer  public mdn;
    Ball     public ball;
    Divider  public divider;
    Feedbase public feed;
    Gem      public dai;
    Gem      public gold;
    Gem      public ruby;
    Gem      public rico;
    Gem      public risk;
    GemFab   public gemfab;
    address  public ricodai;
    address  public ricorisk;
    address  public arico;
    address  public arisk;
    address  public agold;
    address  public aruby;
    address  payable public ahook;
    address  public uniwrapper;
    address payable public bank;

    Guy _bob;
    Guy guy;

    receive () external payable {}

    function rico_mint(uint amt, bool bail) internal {
        uint start_gold = gold.balanceOf(self);
        _bob = new Guy(bank);
        (bytes32 v, uint t) = feedpull(grtag);
        feedpush(grtag, bytes32(RAY * 10000), type(uint).max);
        gold.mint(address(_bob), amt);
        _bob.approve(agold, bank, amt);
        _bob.frob(gilk, address(_bob), abi.encodePacked(amt), int(amt));
        feedpush(grtag, bytes32(0), type(uint).max);
        if (bail) Vow(bank).bail(gilk, address(_bob));
        _bob.transfer(arico, self, amt);
        feedpush(grtag, v, t);
        uint end_gold = gold.balanceOf(self);
        gold.burn(self, end_gold - start_gold);
    }

    function _ink(bytes32 ilk, address usr) internal view returns (uint) {
        return abi.decode(Vat(bank).ink(ilk, usr), (uint));
    }

    function _art(bytes32 ilk, address usr) internal view returns (uint art) {
        art = Vat(bank).urns(ilk, usr);
    }

    function check_gas(uint gas, uint expectedgas) internal view {
        uint usedgas = gas - gasleft();
        if (usedgas < expectedgas) {
            console.log("saved %s gas...currently %s", expectedgas - usedgas, usedgas);
        }
        if (usedgas > expectedgas) {
            console.log("gas increase by %s...currently %s", usedgas - expectedgas, usedgas);
        }
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
        divider.setConfig(tag, Divider.Config(sources, tags));
        // todo quorum?
        Medianizer.Config memory mdnconf =
            Medianizer.Config(new address[](1), new bytes32[](1), 0);
        mdnconf.srcs[0] = address(divider);
        mdnconf.tags[0] = tag;
        mdn.setConfig(tag, mdnconf);
    }

    function make_uniwrapper() internal returns (address deployed) {
        bytes memory args = abi.encode('');
        bytes memory bytecode = abi.encodePacked(vm.getCode(
            "../lib/feedbase/artifacts/src/adapters/UniWrapper.sol:UniWrapper"
        ), args);
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }
    }

    function make_diamond() internal returns (address payable deployed) {
        return payable(address(new BankDiamond()));
    }

    function make_bank() public {
        feed   = new Feedbase();
        gemfab = new GemFab();
        rico  = gemfab.build(bytes32("Rico"), bytes32("RICO"));
        risk  = gemfab.build(bytes32("Rico Riskshare"), bytes32("RISK"));
        arico = address(rico);
        arisk = address(risk);
        uint160 sqrtparx96 = uint160(2 ** 96);
        ricodai  = create_pool(arico, DAI, 500, sqrtparx96);
        ricorisk = create_pool(arico, arisk, RISK_FEE, risk_price);

        uniwrapper = make_uniwrapper();
        bank = make_diamond();

        Ball.IlkParams[] memory ips = new Ball.IlkParams[](1);
        ips[0] = Ball.IlkParams(
            'weth',
            WETH,
            WETH_USD_AGG,
            RAY, // chop
            90 * RAD, // dust
            1000000001546067052200000000, // fee
            100000 * RAD, // line
            RAY, // liqr
            20000, // ttl
            BANKYEAR / 4 // range
        );
        Ball.UniParams memory ups = Ball.UniParams(
            0xC36442b4a4522E871399CD717aBDD847Ab11FE88,
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
            RAY,
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
            0x6B175474E89094C44Da98b954EedeAC495271d0F,
            0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9,
            0x214eD9Da11D2fbe465a6fc601a91E62EbEc1a0D6
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

        rico.approve(bank, type(uint256).max);
        rico.approve(bank, type(uint256).max);

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
        Vat(bank).filk(dilk, 'hook', uint(bytes32(bytes20(address(hook)))));
        Vat(bank).filk(dilk, bytes32('chop'), RAD);
        Vat(bank).filk(dilk, bytes32('line'), init_mint * 10 * RAD);
        Vat(bank).filk(dilk, bytes32('fee'),  1000000001546067052200000000);  // 5%
        // feedpush(dutag, bytes32(RAY), block.timestamp + 1000);
        Vat(bank).filhi(dilk, 'pass', dilk, bytes32(uint(1)));
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
 
        Vat(bank).filk(gilk, 'hook', uint(bytes32(bytes20(address(hook)))));
        // todo fix other chops, should be rays
        Vat(bank).filk(gilk, bytes32('chop'), RAY);
        Vat(bank).filk(gilk, bytes32('line'), init_mint * 10 * RAD);
        Vat(bank).filk(gilk, bytes32('fee'),  1000000001546067052200000000);  // 5%
        feedpush(grtag, bytes32(RAY), block.timestamp + 1000);
        agold = address(gold);
        Vat(bank).filhi(gilk, 'pass', gilk, bytes32(uint(1)));
    }

    function init_ruby() public {
        ruby = Gem(address(gemfab.build(bytes32("Ruby"), bytes32("RUBY"))));
        ruby.mint(self, init_mint * WAD);
        ruby.approve(bank, type(uint256).max);
        Vat(bank).init(rilk, address(hook));
        Vat(bank).filhi(rilk, 'gem', rilk, bytes32(bytes20(address(ruby))));
        Vat(bank).filhi(rilk, 'fsrc', rilk, bytes32(bytes20(self)));
        Vat(bank).filhi(rilk, 'ftag', rilk, rtag);
 
        Vat(bank).filk(rilk, 'hook', uint(bytes32(bytes20(address(hook)))));
        Vat(bank).filk(rilk, bytes32('chop'), RAD);
        Vat(bank).filk(rilk, bytes32('line'), init_mint * 10 * RAD);
        Vat(bank).filk(rilk, bytes32('fee'),  1000000001546067052200000000);  // 5%
        feedpush(rtag, bytes32(RAY), block.timestamp + 1000);
        Vat(bank).filhi(rilk, 'pass', rilk, bytes32(uint(1)));
        aruby = address(ruby);
    }

    function prepguyrico(uint amt, bool bail) internal {
        rico_mint(amt, bail);
        rico.transfer(address(guy), amt);
        guy.approve(arico, bank, UINT256_MAX);
    }

    function assertClose(uint v1, uint v2, uint rel) internal {
        uint abs = v1 / rel;
        assertGt(v1 + abs, v2);
        assertLt(v1 - abs, v2);
    }

}
