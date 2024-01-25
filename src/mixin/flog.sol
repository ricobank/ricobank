/// SPDX-License-Identifier: AGPL-3.0

// Copyright (C) 2021-2024 halys

pragma solidity ^0.8.19;

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
