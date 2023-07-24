// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021-2023 halys

pragma solidity ^0.8.19;

import { Math } from '../mixin/math.sol';
import { Flog } from '../mixin/flog.sol';
import { Gem } from '../../lib/gemfab/src/gem.sol';
import { Feedbase } from '../../lib/feedbase/src/Feedbase.sol';

import { Hook } from './hook.sol';
import { Bank } from '../bank.sol';

contract ERC20Hook is Hook, Bank {
    // per-ilk gem and price feed
    struct Item {
        address gem;   // this ilk's gem
        address fsrc;  // [obj] feedbase `src` address
        bytes32 ftag;  // [tag] feedbase `tag` bytes32
    }

    struct ERC20HookStorage {
        mapping (bytes32 ilk => Item) items;
        // collateral amounts
        mapping (bytes32 ilk => mapping(address usr => uint)) inks;
    }

    function ink(bytes32 i, address u) external view returns (bytes memory data) {
        data = abi.encodePacked(getStorage().inks[i][u]);
    }

    error ErrTransfer();
    error ErrDinkSize();

    bytes32 constant public   INFO     = bytes32(abi.encodePacked('erc20hook.0'));
    bytes32 constant internal POSITION = keccak256(abi.encodePacked(INFO));
    function getStorage() internal pure returns (ERC20HookStorage storage hs) {
        bytes32 pos = POSITION;
        assembly {
            hs.slot := pos
        }
    }

    function frobhook(
        address sender,
        bytes32 i,
        address u,
        bytes calldata _dink,
        int  // dart
    ) external returns (bool safer) {
        ERC20HookStorage storage hs = getStorage();
        // read dink as a single uint
        address gem = hs.items[i].gem;
        if (_dink.length != 32) revert ErrDinkSize();
        int dink = int(uint(bytes32(_dink)));
        uint _ink = add(hs.inks[i][u], dink);
        hs.inks[i][u] = _ink;
        emit NewPalmBytes2('ink', i, bytes32(bytes20(u)), abi.encodePacked(_ink));
        if (sender != address(this)) {
            if (dink > 0) {
                if (!Gem(gem).transferFrom(sender, address(this), uint(dink))) {
                    revert ErrTransfer();
                }
            } else if (dink < 0) {
                if (!Gem(gem).transfer(sender, uint(-dink))) {
                    revert ErrTransfer();
                }
            }
        }
        return dink >= 0;
    }

    function bailhook(
        bytes32 i,
        address u,
        uint256 bill,
        address keeper,
        uint256 rush,
        uint256 cut
    ) external returns (bytes memory) {
        ERC20HookStorage storage hs = getStorage();
        // try to take enough ink to cover the debt
        // cut is RAD, rush is RAY, so bank earns a WAD
        uint ham  = hs.inks[i][u];
        uint sell = ham;
        uint earn = cut / rush;
        if (earn > bill) {
            sell = bill * ham / earn;
            earn = bill;
        }
        uint _ink = hs.inks[i][u] - sell;
        hs.inks[i][u] = _ink;
        emit NewPalmBytes2('ink', i, bytes32(bytes20(u)), abi.encodePacked(_ink));

        Gem gem  = Gem(hs.items[i].gem);
        Gem rico = getBankStorage().rico;
        if (!rico.transferFrom(keeper, address(this), earn)) revert ErrTransfer();
        if (!gem.transfer(keeper, sell)) revert ErrTransfer();
        return abi.encodePacked(sell);
    }

    function safehook(bytes32 i, address u) view public returns (uint, uint) {
        // total value of collateral = ink * price feed val
        ERC20HookStorage storage hs = getStorage();
        Item storage item = hs.items[i];
        (bytes32 val, uint ttl) = getBankStorage().fb.pull(item.fsrc, item.ftag);
        return (uint(val) * hs.inks[i][u], ttl);
    }

    function fili(bytes32 key, bytes32 idx, bytes32 val)
      external {
        ERC20HookStorage storage hs = getStorage();
        if (key == 'gem') {
            hs.items[idx].gem = address(bytes20(val));
        } else if (key == 'fsrc') {
            hs.items[idx].fsrc = address(bytes20(val));
        } else if (key == 'ftag') {
            hs.items[idx].ftag = val;
        } else { revert ErrWrongKey(); }
        emit NewPalm1(concat(INFO, '.', key), idx, val);
    }

    function geti(bytes32 key, bytes32 idx) view external returns (bytes32) {
        ERC20HookStorage storage hs = getStorage();
        if (key == 'gem') {
            return bytes32(bytes20(hs.items[idx].gem));
        } else if (key == 'fsrc') {
            return bytes32(bytes20(hs.items[idx].fsrc));
        } else if (key == 'ftag') {
            return hs.items[idx].ftag;
        } else { revert ErrWrongKey(); }
    }
}
