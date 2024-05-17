import { BigNumber, utils } from 'ethers'
import { send, wad, ray, rad } from 'minihat'
// @ts-ignore
import { ethers } from "hardhat"

export { snapshot, revert, send, wad, ray, rad, apy, N, BANKYEAR, WAD, RAY, RAD, U256_MAX } from 'minihat'

const debug = require('debug')('rico:test')

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

export async function all_gas_used(startblock, endblock) {
  let gas_sum = 0
  for ( let i = startblock; i <= endblock; i++) {
    let block = await ethers.provider.send('eth_getBlockByNumber', [ethers.utils.hexValue(i), true])
    gas_sum += BigNumber.from(block.gasUsed).toNumber()
  }
  return gas_sum
}

export async function task_total_gas(hh, task, params) {
  const startblock = await ethers.provider.getBlockNumber() + 1
  const result = await hh.run(task, params);
  const endblock = await ethers.provider.getBlockNumber()
  const gas = await all_gas_used(startblock, endblock)
  return [gas, result]
}

let snaps  = []
let levels = {}
let level  = 0
const debug_snap = require('debug')('rico:test_snap')
export async function snapshot_name (hre) {
  const _snap = await hre.network.provider.request({
    method: 'evm_snapshot'
  })
  snaps.push(_snap)

  levels[_snap] = level++
  debug_snap(`snapshotting ${_snap} (level ${levels[_snap]})`)
}

export async function revert_name (hre) {
  const _snap = snaps.pop()
  await hre.network.provider.request({
    method: 'evm_revert',
    params: [_snap]
  })

  level--
  debug_snap(`reverting to ${_snap} (level ${levels[_snap]})`)
  await snapshot_name(hre)
}

export async function revert_clear(hre) {
  const _snap = snaps.pop()
  await hre.network.provider.request({
    method: 'evm_revert',
    params: [_snap]
  })
  debug_snap(`reverting to ${_snap} (level ${levels[_snap]}) (no re-snapshot)`)
  level--
  if( level == 0 ) {
    snaps  = []
    levels = {}
  }
}

export async function revert_pop (hre) {
  debug_snap('popping')
  snaps.pop()
  level--
  await revert_name(hre)
}

export async function RICO_mint(vat, dock, RICO, usr, amt : number) {
  await send(vat.suck, usr.address, usr.address, rad(amt))
  await send(dock.connect(usr).exit_rico, vat.address, RICO.address, usr.address, wad(amt))
}

export const gettime = async () => {
    const blocknum = await ethers.provider.getBlockNumber()
    return (await ethers.provider.getBlock(blocknum)).timestamp
}

export const join_pool = async (args) => {
    let nfpm = args.nfpm
    let ethers = args.ethers
    let ali = args.ali
    debug('join_pool')
    if (ethers.BigNumber.from(args.a1.token).gt(ethers.BigNumber.from(args.a2.token))) {
      let a = args.a1;
      args.a1 = args.a2;
      args.a2 = a;
    }

    let spacing = args.tickSpacing;
    let tickmax = 887220
    // full range liquidity
    let tickLower = -tickmax;
    let tickUpper = tickmax;
    let token1 = await ethers.getContractAt('Gem', args.a1.token)
    let token2 = await ethers.getContractAt('Gem', args.a2.token)
    debug('approve tokens ', args.a1.token, args.a2.token)
    await send(token1.approve, nfpm.address, ethers.constants.MaxUint256);
    await send(token2.approve, nfpm.address, ethers.constants.MaxUint256);
    let timestamp = await gettime()
    debug('nfpm mint', nfpm.address)
    let [tokenId, liquidity, amount0, amount1] = await nfpm.callStatic.mint([
          args.a1.token, args.a2.token,
          args.fee,
          tickLower, tickUpper,
          args.a1.amountIn, args.a2.amountIn,
          0, 0, ali.address, timestamp + 1000
    ]);

    await send(nfpm.mint, [
          args.a1.token, args.a2.token,
          args.fee,
          tickLower, tickUpper,
          args.a1.amountIn, args.a2.amountIn,
          0, 0, ali.address, timestamp + 1000
    ]);

    return {tokenId, liquidity, amount0, amount1}
}
