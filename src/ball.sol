/// SPDX-License-Identifier: AGPL-3.0

// The cannonball is the canonical deployment sequence
// implemented as one big contract. You can diff more
// efficient deployment sequences against the result of
// this one.

pragma solidity 0.8.15;

import {Vat} from './vat.sol';
import {Vow} from './vow.sol';
import {Vox} from './vox.sol';
import {BalancerFlower} from './flow.sol';

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

contract Ball {
    error ErrGFHash();
    error ErrFBHash();

    BalancerFlower public flow;
    GemLike public rico;
    GemLike public risk;
    Vat public vat;
    Vow public vow;
    Vox public vox;

    bytes32 public immutable gemFabHash = 0x3d4566ab42065aeb1aa89c121b828f7cce52f908859617efe6f5c85247df2b3b;
    bytes32 public immutable feedbaseHash = 0x444a69f35a859778fe48a0d50c8c24a3d891d8e7287c6db0df0d17f9fcb9c71b;

    constructor(GemFabLike gemfab, address feedbase) {
//        bytes32 codeHash;
//        assembly { codeHash := extcodehash(gemfab) }
//        if (gemFabHash != codeHash) revert ErrGFHash();
//        assembly { codeHash := extcodehash(feedbase) }
//        if (feedbaseHash != codeHash) revert ErrFBHash();

        address roll = msg.sender;

        flow = new BalancerFlower();

        rico = gemfab.build(bytes32("Rico"), bytes32("RICO"));
        risk = gemfab.build(bytes32("Rico Riskshare"), bytes32("RISK"));

        vow = new Vow();
        vox = new Vox();
        vat = new Vat();

        vow.link('flow', address(flow));
        vow.link('vat',  address(vat));
        vow.link('RICO', address(rico));
        vow.link('RISK', address(risk));

        vox.link('fb',  feedbase);
        vox.link('tip', roll);
        vox.link('vat', address(vat));

        vat.file('ceil',  100000e45);
        vat.link('feeds', feedbase);
        vat.link('rico',  address(rico));

        vow.pair(address(risk), 'vel', 1e18);
        vow.pair(address(risk), 'rel', 1e12);
        vow.pair(address(risk), 'cel', 600);
        vow.ward(address(flow), true);

        vat.ward(address(vow),  true);
        vat.ward(address(vox),  true);

        rico.ward(address(vat), true);
        risk.ward(address(vow), true);

        // gem doesn't have give right now
        rico.ward(roll, true);
        rico.ward(address(this), false);
        risk.ward(roll, true);
        risk.ward(address(this), false);

        flow.give(roll);
        vow.give(roll);
        vox.give(roll);
        vat.give(roll);
    }
}
