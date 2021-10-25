import _debug from 'debug'
const debug = _debug('rico:test');
import { expect as want } from 'chai'

import { BigNumber, utils } from 'ethers';
import { BigDecimal } from 'bigdecimal';

const { network } = require('hardhat');

export const BANKYEAR = ((365 * 24) + 6) * 3600;
export const WAD = N(10).pow(N(18))
export const RAY = N(10).pow(N(27))
export const RAD = N(10).pow(N(45))
export const MAXU256 = N(2).pow(N(256)).sub(N(1));
 
export async function wait(t) {
  await network.provider.request({
    method: 'evm_increaseTime',
    params: [t]
  });
}

export async function warp(t) {
  await network.provider.request({
    method: 'evm_setNextBlockTimestamp',
    params: [t]
  });
}

export async function mine(t=undefined) {
  if (t !== undefined) {
    await wait(t);
  }
  await network.provider.request({
    method: 'evm_mine'
  });
}


export async function send(...args) {
  const f = args[0];
  const fargs = args.slice(1);
  const tx = await f(...fargs);
  await tx.wait();
}

export function b32 (arg: any): Buffer {
  if (arg._isBigNumber) {
    const hex = arg.toHexString()
    const buff = Buffer.from(hex.slice(2), 'hex')
    const b32 = utils.zeroPad(buff, 32)
    return b32
  } else if (typeof(arg) == 'string') {
    const b32 = Buffer.from(arg + '\0'.repeat(32 - arg.length));
    return b32
  } else {
    throw new Error(`b32 takes a BigNumber or string, got ${arg}, a ${typeof (arg)}`)
  }
}

export function N(n) : BigNumber {
  return BigNumber.from(n);
}
export function wad (n: number) : BigNumber {
  const bd = new BigDecimal(n);
  const WAD_ = new BigDecimal(WAD.toString());
  const scaled = bd.multiply(WAD_);
  const rounded = scaled.toBigInteger();
  return BigNumber.from(rounded.toString());
}
export function ray (n: number) : BigNumber {
  const bd = new BigDecimal(n);
  const RAY_ = new BigDecimal(RAY.toString());
  const scaled = bd.multiply(RAY_);
  const rounded = scaled.toBigInteger();
  return BigNumber.from(rounded.toString());
}
export function rad (n: number) : BigNumber {
  const bd = new BigDecimal(n);
  const RAD_ = new BigDecimal(RAD.toString());
  const scaled = bd.multiply(RAD_);
  const rounded = scaled.toBigInteger();
  return BigNumber.from(rounded.toString());
}

// Annualized rate, as a ray
export function apy (n : number) : BigNumber {
  // apy = spy^YEAR  ==>  spy = root_{BANKYEAR}(apy)
  //                 ==>  spy = apy ^ (1 / YEAR)
  return ray(Math.pow(n, 1 / BANKYEAR));
}


describe('helpers', ()=>{
  it('wad', ()=>{
    const a = wad(1);
    want(a.toString()).equals("1" + "0".repeat(18))
    const b = wad(2.5);
    want(b.toString()).equals("25" + "0".repeat(17))
  });
  it('apy', ()=>{
    const apy0 = apy(1.05);
  })
});
