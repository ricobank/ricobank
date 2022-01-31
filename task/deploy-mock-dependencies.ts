const debug = require('debug')('ricobank:task')

import { task } from 'hardhat/config'
import { PackBuilder } from 'dpack'

task('deploy-mock-dependencies', '')
.setAction(async (args, hre) => {
  const weth_pack = await hre.run('deploy-mock-weth')
  const bal2_pack = await hre.run('deploy-mock-balancer', {weth_pack: weth_pack})
  const fb_pack = await hre.run('deploy-mock-feedbase')
  const gf_pack = await hre.run('deploy-mock-gemfab')

  const pb = new PackBuilder(hre.network.name)
  await pb.merge(weth_pack, bal2_pack, fb_pack, gf_pack);
  const pack = await pb.build();

  return pack
});
