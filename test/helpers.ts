import { expect as want } from 'chai'

import { BigNumber, utils } from 'ethers'
import { BigDecimal } from 'bigdecimal'

import { wait as _wait, warp as _warp, mine as _mine } from 'minihat'

import * as hre from 'hardhat'

export { send, wad, ray, rad, apy, N, BANKYEAR, WAD, RAY, RAD, U256_MAX } from 'minihat'

const debug = require('debug')('rico:test')

export async function wait (t) {
  await _wait(hre, t)
}

export async function warp (t) {
  await _warp(hre, t)
}

export async function mine (t = undefined) {
  await _mine(hre, t)
}

export function b32 (arg: any): Buffer {
  if (arg._isBigNumber) {
    const hex = arg.toHexString()
    const buff = Buffer.from(hex.slice(2), 'hex')
    const b32 = utils.zeroPad(buff, 32)
    return b32
  } else if (typeof (arg) === 'string') {
    const b32 = Buffer.from(arg + '\0'.repeat(32 - arg.length))
    return b32
  } else {
    throw new Error(`b32 takes a BigNumber or string, got ${arg}, a ${typeof (arg)}`)
  }
}
