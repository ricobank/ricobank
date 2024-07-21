/// SPDX-License-Identifier: AGPL-3.0

// Copyright (C) 2024 Free Software Foundation, in loving memory of Nikolai

pragma solidity ^0.8.25;

abstract contract Palm {
    event NewPalm0(
        bytes32 indexed key
      , bytes32 val
    );
    event NewPalm1(
        bytes32 indexed key
      , bytes32 indexed idx0
      , bytes32 val
    );
}
