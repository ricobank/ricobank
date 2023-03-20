/// SPDX-License-Identifier: AGPL-3.0

// The cannonball is the canonical deployment sequence
// implemented as one big contract. You can diff more
// efficient deployment sequences against the result of
// this one.

pragma solidity 0.8.19;

import {Vat} from './vat.sol';
import {Vow} from './vow.sol';
import {Vox} from './vox.sol';
import {UniFlower} from './flow.sol';
import {Feedbase} from "../lib/feedbase/src/Feedbase.sol";
import {Divider} from "../lib/feedbase/src/combinators/Divider.sol";
import {UniswapV3Adapter} from "../lib/feedbase/src/adapters/UniswapV3Adapter.sol";
import {Medianizer} from "../lib/feedbase/src/Medianizer.sol";
import {TWAP} from "../lib/feedbase/src/combinators/TWAP.sol";
import {ChainlinkAdapter} from "../lib/feedbase/src/adapters/ChainlinkAdapter.sol";
import {Math} from '../src/mixin/math.sol';
import {Pool} from '../src/mixin/pool.sol';
import { IUniswapV3Pool } from "../src/TEMPinterface.sol";
import {ERC20Hook} from './hook/ERC20hook.sol';

interface GemFabLike {
    function build(
        bytes32 name,
        bytes32 symbol
    ) payable external returns (GemLike);
}

interface GemLike {
    function ward(address usr,
        bool authed
    ) payable external;
}

contract Ball is Math, Pool {
    error ErrGFHash();
    error ErrFBHash();

    bytes32 internal constant RICO_DAI_TAG = "ricodai";
    bytes32 internal constant DAI_RICO_TAG = "dairico";
    bytes32 internal constant XAU_USD_TAG = "xauusd";
    bytes32 internal constant DAI_USD_TAG = "daiusd";
    bytes32 internal constant RICO_XAU_TAG = "ricoxau";
    bytes32 internal constant RICO_REF_TAG = "ricoref";
    uint160 internal constant risk_price = 2 ** 96;
    uint24  internal constant RICO_FEE = 500;
    uint24  internal constant RISK_FEE = 3000;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public rico;
    address public risk;
    UniFlower public flow;
    Vat public vat;
    Vow public vow;
    Vox public vox;
    ERC20Hook public hook;

    IUniswapV3Pool public ricodai;
    IUniswapV3Pool public ricorisk;

    Medianizer public mdn;
    UniswapV3Adapter public adapt;
    Divider public divider;
    ChainlinkAdapter public cladapt;
    TWAP public twap;
   
    address constant DAI_USD_AGG = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address constant XAU_USD_AGG = 0x214eD9Da11D2fbe465a6fc601a91E62EbEc1a0D6;
    struct IlkParams {
        bytes32 ilk;
        address gem;
        address pool;
        uint    chop;
        uint    dust;
        uint    fee;
        uint    line;
        uint    liqr;
        UniFlower.Ramp ramp;
        uint    ttl;
        uint    range;
    }

    struct BallArgs {
        address gemfab;
        address feedbase;
        address factory;
        address router;
        address roll;
        uint    sqrtpar;
        uint    ceil;
        uint    ricodairange;
        uint    ricodaittl;
        uint    daiusdttl;
        uint    xauusdttl;
        uint    twaprange;
        uint    twapttl;
        UniFlower.Ramp ricoramp;
        UniFlower.Ramp riskramp;
        UniFlower.Ramp mintramp;
    }

    constructor(
        BallArgs    memory args,
        IlkParams[] memory ilks
    ) payable {
        flow = new UniFlower();

        rico = address(GemFabLike(args.gemfab).build(bytes32("Rico"), bytes32("RICO")));
        risk = address(GemFabLike(args.gemfab).build(bytes32("Rico Riskshare"), bytes32("RISK")));

        vow = new Vow();
        vat = new Vat();

        hook = new ERC20Hook(address(vat), address(flow), rico);

        vat.prod(args.sqrtpar ** 2 / RAY);

        vow.link('flow', address(flow));
        vow.link('vat',  address(vat));
        vow.link('RICO', rico);
        vow.link('RISK', risk);

        vat.file('ceil',  args.ceil);
        vat.link('feeds', args.feedbase);
        vat.link('rico',  address(rico));

        vow.ward(address(flow), true);
        vat.ward(address(vow), true);
        hook.ward(address(flow), true); // flowback
        hook.ward(address(vat), true);  // grabhook, frobhook

        mdn = new Medianizer(args.feedbase);

        {
            uint160 sqrtparx96 = uint160(args.sqrtpar * (2 ** 96) / RAY);
            ricodai = create_pool(args.factory, rico, DAI, 500, sqrtparx96);
        }

        adapt = new UniswapV3Adapter(Feedbase(args.feedbase));
        divider = new Divider(args.feedbase, RAY);
        twap = new TWAP(args.feedbase);
        flow.setSwapRouter(args.router);
        Medianizer.Source[] memory mdn_sources = new Medianizer.Source[](1);
        mdn_sources[0].src = address(divider);
        for (uint i = 0; i < ilks.length; i++) {
            IlkParams memory ilkparams = ilks[i];
            bytes32 ilk = ilkparams.ilk;
            address gem = ilkparams.gem;
            address pool = ilkparams.pool;
            vat.init(ilk, address(hook), address(mdn), concat(ilk, 'rico'));
            mdn_sources[0].tag = concat(ilk, 'rico');
            mdn.setSources(concat(ilk, 'rico'), mdn_sources);
            hook.link(ilk, gem);
            hook.grant(gem);
            vat.filk(ilk, 'chop', ilkparams.chop);
            vat.filk(ilk, 'dust', ilkparams.dust);
            vat.filk(ilk, 'fee',  ilkparams.fee);  // 5%
            vat.filk(ilk, 'line', ilkparams.line);
            vat.filk(ilk, 'liqr', ilkparams.liqr);
            hook.list(gem, true);
            vow.grant(gem);

            bytes memory f;
            bytes memory r;
            if (gem == DAI) {
                address [] memory a2 = new address[](2);
                uint24  [] memory f1 = new uint24 [](1);
                a2[0] = DAI;
                a2[1] = rico;
                f1[0] = RICO_FEE;
                (f, r) = create_path(a2, f1);
                // dai/rico feed created later
            } else {
                // To avoid STD
                {
                    address [] memory addr3 = new address[](3);
                    uint24  [] memory fees2 = new uint24 [](2);
                    addr3[0] = gem;
                    addr3[1] = DAI;
                    addr3[2] = rico;
                    fees2[0] = IUniswapV3Pool(pool).fee();
                    fees2[1] = RICO_FEE;
                    (f, r) = create_path(addr3, fees2);
                }

                bytes32 tag = concat(ilk, 'dai');
                adapt.setConfig(
                    tag,
                    UniswapV3Adapter.Config(pool, ilkparams.ttl, ilkparams.range, gem > DAI)
                );

                // TODO: Check what to use for range, ttl
                twap.setConfig(tag, TWAP.Config(address(adapt), tag, args.twaprange, args.twapttl));
                address[] memory ss = new address[](2);
                bytes32[] memory ts = new bytes32[](2);
                ss[0] = address(twap); ts[0] = tag;
                ss[1] = address(adapt); ts[1] = RICO_DAI_TAG;
                divider.setConfig(concat(ilk, 'rico'), Divider.Config(ss, ts));
            }

            flow.setPath(gem, rico, f, r);
            hook.pair(gem, "vel", ilkparams.ramp.vel);
            hook.pair(gem, "rel", ilkparams.ramp.rel);
            hook.pair(gem, "bel", ilkparams.ramp.bel);
            hook.pair(gem, "cel", ilkparams.ramp.cel);
            hook.pair(gem, "del", ilkparams.ramp.del);
        }

        GemLike(rico).ward(address(vat), true);
        GemLike(risk).ward(address(vow), true);

        // gem doesn't have give right now
        address roll = args.roll;
        GemLike(rico).ward(roll, true);
        GemLike(rico).ward(address(this), false);
        GemLike(risk).ward(roll, true);
        // don't unward for risk yet...need to create pool

        // todo move out of ball for gas, either calc gemfab create address or split ball into parts if too big
        address [] memory addr2 = new address[](2);
        uint24  [] memory fees1 = new uint24 [](1);
        bytes memory fore;
        bytes memory rear;
        addr2[0] = risk;
        addr2[1] = rico;
        fees1[0] = RISK_FEE;
        (fore, rear) = create_path(addr2, fees1);
        flow.setPath(risk, rico, fore, rear);
        // todo ramp config
        vow.pair(risk, "vel", args.riskramp.vel);
        vow.pair(risk, "rel", args.riskramp.rel);
        vow.pair(risk, "bel", args.riskramp.bel);
        vow.pair(risk, "cel", args.riskramp.cel);
        vow.pair(risk, "del", args.riskramp.del);
        vow.pair(address(0), "vel", args.mintramp.vel);
        vow.pair(address(0), "rel", args.mintramp.rel);
        vow.pair(address(0), "bel", args.mintramp.bel);
        vow.pair(address(0), "cel", args.mintramp.cel);
        vow.pair(address(0), "del", args.mintramp.del);

        flow.setPath(rico, risk, rear, fore);
        vow.pair(rico, "vel", args.ricoramp.vel);
        vow.pair(rico, "rel", args.ricoramp.rel);
        vow.pair(rico, "bel", args.ricoramp.bel);
        vow.pair(rico, "cel", args.ricoramp.cel);
        vow.pair(rico, "del", args.ricoramp.del);

        vow.grant(rico);
        vow.grant(risk);

        flow.give(roll);
        vow.give(roll);
        hook.give(roll);
        ricorisk = create_pool(args.factory, rico, risk, RISK_FEE, risk_price);
        // |------------------------->divider--------->twap------>| (usd/rico)
        // |                              |                       |
        // |                             inv                      |
        // |                              |                       |
        // |                         rico/dai                     |
        // |   Rico/Dai AMM ------------->|                       |
        // --- DAI/USD CL -- divider---->divider------>twap---->prog-->inv-->RICO/REF
        //     XAU/USD CL ----|                   ^
        //                                  (xau/rico)
        adapt.setConfig(
            RICO_DAI_TAG,
            UniswapV3Adapter.Config(address(ricodai), args.ricodairange, args.ricodaittl, DAI < rico)
        );
        adapt.ward(roll, true);
        adapt.ward(address(this), false);

        // dai/rico = 1 / (rico/dai)
        {
            address[] memory sources = new address[](2);
            bytes32[] memory tags    = new bytes32[](2);
            Feedbase(args.feedbase).push(bytes32("ONE"), bytes32(RAY), type(uint).max);
            sources[0] = address(this); tags[0] = bytes32("ONE");
            sources[1] = address(adapt); tags[1] = RICO_DAI_TAG;
            divider.setConfig(DAI_RICO_TAG, Divider.Config(sources, tags));
        }

        cladapt = new ChainlinkAdapter(args.feedbase);
        cladapt.setConfig(XAU_USD_TAG, ChainlinkAdapter.Config(XAU_USD_AGG, args.xauusdttl, RAY));
        cladapt.setConfig(DAI_USD_TAG, ChainlinkAdapter.Config(DAI_USD_AGG, args.daiusdttl, RAY));
        {
            address[] memory src3 = new address[](3);
            bytes32[] memory tag3 = new bytes32[](3);
            src3[0] = address(cladapt); tag3[0] = DAI_USD_TAG;
            src3[1] = address(divider); tag3[1] = DAI_RICO_TAG;
            src3[2] = address(cladapt); tag3[2] = XAU_USD_TAG;
            divider.setConfig(RICO_XAU_TAG, Divider.Config(src3, tag3));
        }
        twap.setConfig(RICO_XAU_TAG, TWAP.Config(address(divider), RICO_XAU_TAG, args.twaprange, args.twapttl));
        mdn_sources[0] = Medianizer.Source(address(twap), RICO_XAU_TAG);
        mdn.setSources(RICO_REF_TAG, mdn_sources);

        divider.ward(roll, true);
        divider.ward(address(this), false);

        mdn.ward(roll, true);

        cladapt.look(XAU_USD_TAG);
        (bytes32 ref,) = Feedbase(args.feedbase).pull(address(cladapt), XAU_USD_TAG);
        vox = new Vox(uint256(ref));
        vox.link('fb',  args.feedbase);
        vox.link('tip', args.roll);
        vox.link('vat', address(vat));
        vox.link('tip', address(mdn));
        vox.file('tag', RICO_REF_TAG);
        vat.ward(address(vox), true);
        vat.give(roll);
        vox.give(roll);
    }

    function concat(bytes32 a, bytes32 b) internal pure returns (bytes32 res) {
        uint i;
        while (true) {
            if (a[i] == 0) break;
            unchecked{ i++; }
        }
        res = a | (b >> (i << 3));
    }
}
