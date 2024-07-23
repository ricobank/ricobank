/// SPDX-License-Identifier: AGPL-3.0

// Copyright (C) 2022-2024 Free Software Foundation, in loving memory of Nikolai

pragma solidity ^0.8.25;

abstract contract Flog {
    event NewFlog(
        address indexed caller
      , bytes4 indexed sig
      , bytes data
    );

    // similar to ds-note - emits function call data
    // use at beginning of external state modifying functions
    modifier _flog_ {
        emit NewFlog(msg.sender, msg.sig, msg.data);
        _;
    }
}
