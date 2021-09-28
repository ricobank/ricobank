import _debug from 'debug'
const debug = _debug('rico:test');
import { expect as want } from 'chai'

import { BigNumber } from 'ethers';
import { BigDecimal } from 'bigdecimal';

export const BANKYEAR = ((365 * 24) + 6) * 3600;
export const WAD = N(10).pow(N(18))
export const RAY = N(10).pow(N(27))
export const RAD = N(10).pow(N(45))

export async function send(...args) {
  const f = args[0];
  const fargs = args.slice(1);
  const tx = await f(...fargs);
  await tx.wait();
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
