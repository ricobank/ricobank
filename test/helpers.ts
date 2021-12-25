import { utils } from 'ethers'
import { send } from 'minihat'

export { snapshot, revert, send, wad, ray, rad, apy, N, BANKYEAR, WAD, RAY, RAD, U256_MAX } from 'minihat'

const debug = require('debug')('rico:test')
const ramp_members = ['vel', 'rel', 'bel', 'cel']

export function b32 (arg: any): Uint8Array {
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

export async function set_ramp(contract, vals, gem? ) {
  for (let ramp_member of ramp_members) {
    if (gem) await send(contract.filem, gem.address, b32(ramp_member), vals[ramp_member]);
    else await send(contract.file, b32(ramp_member), vals[ramp_member]);
  }
}
