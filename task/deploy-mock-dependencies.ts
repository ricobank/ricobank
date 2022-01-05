const debug = require('debug')('ricobank:task')

import { task } from 'hardhat/config'
import { PackBuilder } from 'dpack'

task('deploy-mock-dependencies', '')
.setAction(async (args, hre) => {
  const fb_pack = await hre.run('deploy-mock-feedbase')
  const gf_pack = await hre.run('deploy-mock-gemfab')
  const bal2_pack = await hre.run('deploy-mock-balancer', {WETH:{address:fb_pack.objects.feedbase.address}})

  const pb = new PackBuilder(hre.network.name)
  await pb.merge(fb_pack, gf_pack, bal2_pack);
  const pack = await pb.build();

  return pack
});
