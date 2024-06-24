import { task } from 'hardhat/config'
const debug = require('debug')('ricobank:task')
const dpack = require('@etherpacks/dpack')
import { b32, send } from 'minihat'

task('deploy-tokens', '')
.addOptionalParam('gfpackcid', 'gemfab pack passed as cid cli string, alternative to gf_pack obj passed from another task')
.addOptionalParam('outfile', 'output JSON file')
.addOptionalParam('mock', 'mock mode')
.addOptionalParam('gasLimit', 'per-tx gas limit')
.addParam('netname', 'network to load from')
.setAction(async (args, hre) => {
  debug('deploy tokens')

  const [ ali ]  = await hre.ethers.getSigners()
  const settings = require('./settings.json')[args.netname]

  debug('deploy rico')
  const gf_dapp = await dpack.load(args.gf_pack ?? args.gfpackcid, hre.ethers, ali)
  let rico_addr
  if (settings.rico) {
    rico_addr = settings.rico
  } else {
    rico_addr = await gf_dapp.gemfab.callStatic.build(
      b32(settings.rico_name), b32(settings.rico_symbol)
    );
    await send(gf_dapp.gemfab.build, b32(settings.rico_name), b32(settings.rico_symbol), {gasLimit: args.gasLimit})
  }

  debug('deploy risk', args.riskname, args.risksym)
  let risk_addr
  if (settings.risk) {
    // risk already deployed
    risk_addr = settings.risk
  } else {
    risk_addr = await gf_dapp.gemfab.callStatic.build(
        b32(settings.risk_name), b32(settings.risk_symbol)
    )
    await send(
      gf_dapp.gemfab.build,
      b32(settings.risk_name), b32(settings.risk_symbol), {gasLimit: args.gasLimit}
    )
  }

  // pack the system-required tokens
  const pb = new dpack.PackBuilder(hre.network.name)
  const gem_artifact = await dpack.getIpfsJson(gf_dapp._types.Gem.artifact['/'])
  if (args.mint) {
    const gem_type = await hre.ethers.ContractFactory.fromSolidity(gem_artifact, ali)
    await gem_type.attach(risk_addr).mint(ali.address, args.mint)
  }

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
