import { want, b32, fail } from 'minihat'
import { task_total_gas } from './helpers'

const debug = require('debug')('ricobank:test')
import * as hh from 'hardhat'
const dpack = require('@etherpacks/dpack')
const GASLIMIT = '1000000000'

describe('deployments', ()=>{
  describe('deploy-ricobank task', async ()=> {
    it('deploy', async () => {
      debug(Object.keys(hh))
      debug(Object.keys(hh.network))
      debug(hh.network.name)
      const [gas, pack] = await task_total_gas(hh, 'deploy-ricobank', {mock:'true', netname: 'ethereum', tokens: './tokens.json'})
      const expectedgas = 42530025
      want(gas).to.be.at.most(expectedgas)
      if (gas < expectedgas) {
          console.log("deploy saved", expectedgas - gas, "gas...currently", gas)
      }
      want(pack.objects.bank).exists

      let [ali] = await hh.ethers.getSigners()
      const dapp = await dpack.load(pack, hh.ethers, ali)
      let ploker = dapp.ploker
      for (const tag of ['weth:rico', 'rico:risk', 'risk:rico', 'rico:ref']) {
          debug(`ploking ${tag}`)
          await ploker.ploke(b32(tag), { gasLimit: GASLIMIT })
      }
      await fail('ErrNoConfig', ploker.ploke, b32('ricoref'), { gasLimit: GASLIMIT })
    })
  })
})
