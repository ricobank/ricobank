import _debug from 'debug'
const debug = _debug('rico:test');
import { expect as want } from 'chai'

import { ethers, artifacts } from 'hardhat'

import { BN } from 'bn.js'

describe('Vat', () => {
  let ali, bob, cat;
  let ALI, BOB, CAT;
  let vat;
  before(async() => {
    [ali, bob, cat] = await ethers.getSigners();
    [ALI, BOB, CAT] = [ali, bob, cat].map(signer => signer.address);
  });
  beforeEach(async() => {
    const vat_type = await ethers.getContractFactory('./src/vat.sol:Vat', ali);
    vat = await vat_type.deploy();
  });

  it('init conditions', async()=>{
    const isWarded = await vat.wards(ALI);
    debug(isWarded);
  });

});
