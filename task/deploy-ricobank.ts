import { task } from 'hardhat/config'

const debug = require('debug')('ricobank:task')
const dpack = require('@etherpacks/dpack')
import { b32, ray, rad, send, wad, BANKYEAR } from 'minihat'

task('deploy-ricobank', '')
  .addOptionalParam('mock', 'Ignore dependency args and deploy new mock dependencies')
  .addOptionalParam('dependencies', 'Pack with all required dependencies')
  .addOptionalParam('arb', 'Arbitrum deploy')
  .addOptionalParam('writepack', 'write pack to pack dir')
  .addOptionalParam('gasLimit', 'per-tx gas limit')
  .addOptionalParam('ipfs', 'add packs to ipfs')
  .addParam('netname', 'network name to load packs from')
  .setAction(async (args, hre) => {
    debug('network name in task:', hre.network.name)
    const ethers    = hre.ethers
    const BN        = ethers.BigNumber
    const constants = ethers.constants

    const [ali]  = await ethers.getSigners()
    const bn2b32 = (bn) => ethers.utils.hexZeroPad(bn.toHexString(), 32)

    let deps_pack
    if (args.dependencies) {
        try {
            deps_pack = JSON.parse(args.dependencies);
        } catch (e) {
            // allow deps to be passed as ipfs CID
            deps_pack = await dpack.getIpfsJson(args.dependencies);
        }
    } else {
        deps_pack = await hre.run(
          'deploy-dependencies',
          {
              mock:    args.mock,
              gfpackcid: args.gfpackcid,
              ipfs: args.ipfs,
              mint: args.mint,
              netname: args.netname
          }
        )
    }

    const deps = await dpack.load(deps_pack, ethers, ali)

    const pb = new dpack.PackBuilder(hre.network.name)

    const settings = require('./settings.json')[args.netname]

    // base diamond contract (address will be bank address)
    const bank_artifact = require('../artifacts/src/bank.sol/Bank.json')
    const bank_type = ethers.ContractFactory.fromSolidity(bank_artifact, ali)
    debug('deploying bank')

    const bankargs = {
        rico: deps.rico.address,
        risk: deps.risk.address,
        par:  ray(settings.par),
        fee:  ray(settings.fee),
        dust: ray(settings.dust),
        chop: ray(settings.chop),
        liqr: ray(settings.liqr),
        pep: settings.pep,
        pop: ray(settings.pop),
        pup: ray(settings.pup),
        gif:  wad(settings.gif),
        pex:  settings.pex,
        wel:  ray(settings.wel),
        dam:  ray(settings.dam),
        mop:  ray(settings.mop),
        lax:  ray(settings.lax),
        how:  ray(settings.how),
        cap:  ray(settings.cap),
        way:  ray(settings.way)
    }

    const bank = await bank_type.deploy(bankargs, {gasLimit: args.gasLimit})

    debug(`done deploying bank at ${bank.address}`)

    debug('ward rico and risk')
    await send(deps.rico.ward, bank.address, 1)
    await send(deps.risk.ward, bank.address, 1)


    debug('packing bank')
    await pb.packObject({
        objectname: 'bank',
        address: bank.address,
        typename: 'Bank',
        artifact: bank_artifact
    }, true)
    debug('all packed, merging')

    const pack = (await pb.merge(deps_pack)).build()

    if (args.writepack) {
        const outfile = require('path').join(
            __dirname, `../pack/ricobank_${hre.network.name}.dpack.json`
        )
        const packstr = JSON.stringify(pack, null, 2)
        require('fs').writeFileSync(outfile, packstr)
    }

    if (args.ipfs) {
      console.log("deploy-ricobank IPFS CIDs:")
      let cid = await dpack.putIpfsJson(deps_pack, true)
      console.log(`  Dependencies: ${cid}`)
      cid = await dpack.putIpfsJson(pack, true)
      console.log(`  Ricobank: ${cid}`)
    }

    return pack
  })
