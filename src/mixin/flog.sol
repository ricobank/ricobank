/// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.15;

abstract contract Flog {
    event NewFlog(
        address indexed caller
      , bytes4 indexed sig
      , bytes data
    ) anonymous;

    modifier _flog_ {
        emit NewFlog(msg.sender, msg.sig, msg.data);
        _;
    }
}