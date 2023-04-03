import { task } from 'hardhat/config'
const dpack = require('@etherpacks/dpack')
import { b32, send } from 'minihat'

task('deploy-mock-tokens', '')
.setAction(async (args, hre) => {
  const [ signer ]  = await hre.ethers.getSigners()
  const gf_dapp = await dpack.load(args.gf_pack, hre.ethers, signer)
  const rico_receipt = await send(gf_dapp.gemfab.build, b32("Rico"), b32("RICO"))
  const risk_receipt = await send(gf_dapp.gemfab.build, b32("Rico Riskshare"), b32("RISK"))
  const rico_addr = rico_receipt.events.find(e => e.event == "Build").args.gem
  const risk_addr = risk_receipt.events.find(e => e.event == "Build").args.gem

  const dai_addr = "0x6B175474E89094C44Da98b954EedeAC495271d0F"
  const uni_dapp = await dpack.load(args.uni_pack, hre.ethers, signer)
  let [t0, t1] = [rico_addr, risk_addr];
  if (hre.ethers.BigNumber.from(t1).lt(hre.ethers.BigNumber.from(t0))) [t1, t0] = [rico_addr, risk_addr]
  const ricorisk_receipt = await send(uni_dapp.uniswapV3Factory.createPool, t0, t1, 3000)
  const ricorisk_addr = ricorisk_receipt.events.find(e => e.event == "PoolCreated").args.pool;
  [t0, t1] = [rico_addr, dai_addr]
  if (hre.ethers.BigNumber.from(t1).lt(hre.ethers.BigNumber.from(t0))) [t1, t0] = [rico_addr, dai_addr]
  const ricodai_receipt = await send(uni_dapp.uniswapV3Factory.createPool, t0, t1, 500)
  const ricodai_addr = ricodai_receipt.events.find(e => e.event == "PoolCreated").args.pool

  const pb = new dpack.PackBuilder(hre.network.name)
  const gem_artifact = await dpack.getIpfsJson(gf_dapp._types.Gem.artifact['/'])
  const pool_artifact = await dpack.getIpfsJson(uni_dapp._types.UniswapV3Pool.artifact['/'])
  await pb.packObject({
    objectname: 'rico',
    typename: 'Gem',
    artifact: gem_artifact,
    address: rico_addr
  }, false)
  await pb.packObject({
    objectname: 'risk',
    typename: 'Gem',
    artifact: gem_artifact,
    address: risk_addr
  }, false)
  await pb.packObject({
    objectname: 'ricorisk',
    typename: 'UniswapV3Pool',
    artifact: pool_artifact,
    address: ricorisk_addr
  }, false)
  await pb.packObject({
    objectname: 'ricodai',
    typename: 'UniswapV3Pool',
    artifact: pool_artifact,
    address: ricodai_addr
  }, false)
  const pack = await pb.build()
  const str = JSON.stringify(pack, null, 2)
  if (args.stdout) {
      console.log(str)
  }
  if (args.outfile) {
      require('fs').writeFileSync(args.outfile, str)
  }
  return pack
})
