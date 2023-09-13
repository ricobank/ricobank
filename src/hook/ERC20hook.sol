// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021-2023 halys

pragma solidity ^0.8.19;

import { Bank, Gem } from '../bank.sol';
import { Hook } from './hook.sol';

// hook that interprets ink as a single uint and dink as a single int.
contract ERC20Hook is Hook, Bank {

    // per-ilk gem and price feed
    struct Item {
        address gem;   // this ilk's gem
        address fsrc;  // [obj] feedbase `src` address
        bytes32 ftag;  // [tag] feedbase `tag` bytes32
    }

    struct ERC20HookStorage {
        mapping (bytes32 ilk => Item) items; // token info
        mapping (bytes32 i => mapping(address u => uint)) inks; // amount
    }

    bytes32 constant public   INFO     = bytes32(abi.encodePacked('erc20hook.0'));
    bytes32 constant internal POSITION = keccak256(abi.encodePacked(INFO));
    function getStorage() internal pure returns (ERC20HookStorage storage hs) {
        bytes32 pos = POSITION;
        assembly {
            hs.slot := pos
        }
    }

    error ErrTransfer();
    error ErrDinkSize();

    function ink(bytes32 i, address u) external view returns (bytes memory data) {
        data = abi.encodePacked(getStorage().inks[i][u]);
    }

    function frobhook(
        address sender, bytes32 i, address u, bytes calldata _dink, int
    ) external returns (bool safer) {
        ERC20HookStorage storage hs = getStorage();

        // read dink as a single uint
        if (_dink.length != 32) revert ErrDinkSize();
        int dink = int(uint(bytes32(_dink)));

        // update balance before transfering tokens
        uint _ink     = add(hs.inks[i][u], dink);
        hs.inks[i][u] = _ink;
        emit NewPalmBytes2('erc20hook.0.ink', i, bytes32(bytes20(u)), abi.encodePacked(_ink));

        Gem gem = Gem(hs.items[i].gem);
        if (dink > 0) {

            // pull tokens from sender
            if (!gem.transferFrom(sender, address(this), uint(dink))) {
                revert ErrTransfer();
            }

        } else if (dink < 0) {

            // return tokens to sender
            if (!gem.transfer(sender, uint(-dink))) {
                revert ErrTransfer();
            }

        }

        // safer if this call added tokens to ink
        return dink >= 0;
    }

    function bailhook(
        bytes32 i, address u, uint256 bill,
        address keeper, uint256 rush, uint256 cut
    ) external returns (bytes memory) {
        ERC20HookStorage storage hs = getStorage();
        VatStorage       storage vs = getVatStorage();

        // cut is RAD, rush is RAY, so bank earns a WAD.
        // sell - sold collateral
        // earn - rico "earned" by bank in this liquidation
        uint ham  = hs.inks[i][u];
        uint sell = ham;
        uint earn = cut / rush;

        // clamp `sell` so bank only gets enough to underwrite urn.
        if (earn > bill) {
            sell = bill * ham / earn;
            earn = bill;
        }

        // update collateral balance
        uint _ink     = hs.inks[i][u] - sell;
        hs.inks[i][u] = _ink;
        emit NewPalmBytes2('erc20hook.0.ink', i, bytes32(bytes20(u)), abi.encodePacked(_ink));

        // update joy to help cancel out sin
        uint mood = vs.joy + earn;
        vs.joy = mood;
        emit NewPalm0('joy', bytes32(mood));

        // trade collateral with keeper for rico
        getBankStorage().rico.burn(keeper, earn);
        if (!Gem(hs.items[i].gem).transfer(keeper, sell)) revert ErrTransfer();

        return abi.encodePacked(sell);
    }

    function safehook(bytes32 i, address u) view public returns (uint, uint) {
        ERC20HookStorage storage hs = getStorage();
        Item storage item = hs.items[i];

        // total value of collateral == ink * price feed val
        (bytes32 val, uint ttl) = getBankStorage().fb.pull(item.fsrc, item.ftag);
        return (uint(val) * hs.inks[i][u], ttl);
    }

    function file(bytes32 key, bytes32 i, bytes32[] calldata xs, bytes32 val)
      external {
        ERC20HookStorage storage hs = getStorage();

        if (xs.length == 0) {
            if (key == 'gem') {
                hs.items[i].gem = address(bytes20(val));
            } else if (key == 'fsrc') {
                hs.items[i].fsrc = address(bytes20(val));
            } else if (key == 'ftag') {
                hs.items[i].ftag = val;
            } else { revert ErrWrongKey(); }
            emit NewPalm1(concat(INFO, '.', key), i, val);
        } else {
            revert ErrWrongKey();
        }
    }

    function get(bytes32 key, bytes32 i, bytes32[] calldata xs)
      view external returns (bytes32) {
        ERC20HookStorage storage hs = getStorage();

        if (xs.length == 0) {
            if (key == 'gem') {
                return bytes32(bytes20(hs.items[i].gem));
            } else if (key == 'fsrc') {
                return bytes32(bytes20(hs.items[i].fsrc));
            } else if (key == 'ftag') {
                return hs.items[i].ftag;
            } else { revert ErrWrongKey(); }
        } else {
            revert ErrWrongKey();
        }
    }
}
