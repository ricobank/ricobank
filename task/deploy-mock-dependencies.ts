const debug = require('debug')('ricobank:task')

import { task } from 'hardhat/config'
const dpack = require('@etherpacks/dpack')

task('deploy-mock-dependencies', '')
.setAction(async (args, hre) => {
  const weth_pack = await hre.run('deploy-mock-weth')
  const uni_pack = await hre.run('deploy-mock-uniswap', {weth_pack: weth_pack})
  const fb_pack = await hre.run('deploy-mock-feedbase')
  const gf_pack = await hre.run('deploy-mock-gemfab')
  const tokens_pack = await hre.run('deploy-mock-tokens', {gf_pack: gf_pack, uni_pack: uni_pack})

  const pb = new dpack.PackBuilder(hre.network.name)
  await pb.merge(weth_pack, uni_pack, fb_pack, gf_pack, tokens_pack);
  const pack = await pb.build();

  return pack
});
