import { BigNumber, utils } from 'ethers'
import { send } from 'minihat'
import { ethers } from "hardhat"

export { snapshot, revert, send, wad, ray, rad, apy, N, BANKYEAR, WAD, RAY, RAD, U256_MAX } from 'minihat'

const debug = require('debug')('rico:test')
const ramp_members = ['vel', 'rel', 'bel', 'cel']
export const ADDRZERO = '0x' + '00'.repeat(20)

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

export async function file_ramp(contract, vals) {
  for (let ramp_member of ramp_members) {
    await send(contract.file, b32(ramp_member), vals[ramp_member]);
  }
}

export async function filem_ramp(gem, contract, vals) {
  for (let ramp_member of ramp_members) {
    await send(contract.filem, gem.address, b32(ramp_member), vals[ramp_member]);
  }
}

export async function all_gas_used() {
  const block_num = await ethers.provider.getBlockNumber()
  let gas_sum = 0
  for ( let i = 1; i <= block_num; i++) {
    let block = await ethers.provider.send('eth_getBlockByNumber', [ethers.utils.hexValue(i), true])
    gas_sum += BigNumber.from(block.gasUsed).toNumber()
  }
  return gas_sum
}

export async function task_total_gas(hh, task, params) {
  const gas0 = await all_gas_used()
  const result = await hh.run(task, params);
  const gas1 = await all_gas_used()
  return [gas1 - gas0, result]
}

