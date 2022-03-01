/// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.10;

abstract contract Flog {
    event Flog(
        address indexed caller
      , bytes4 indexed sig
      , bytes data
    ) anonymous;

    modifier _flog_ {
        emit Flog(msg.sender, msg.sig, msg.data);
        _;
    }
}