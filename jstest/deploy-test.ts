import { want } from 'minihat'
import { task_total_gas } from './helpers'

const debug = require('debug')('ricobank:test')
const hh = require('hardhat')

describe('deployments', ()=>{
  describe('deploy-ricobank task', async ()=> {
    it('deploy', async () => {
      debug(Object.keys(hh))
      debug(Object.keys(hh.network))
      debug(hh.network.name)
      const [gas, pack] = await task_total_gas(hh, 'deploy-ricobank', {mock:'true'})
      const expectedgas = 44569709
      want(gas).to.be.at.most(expectedgas)
      if (gas < expectedgas) {
          console.log("deploy saved", expectedgas - gas, "gas...currently", gas)
      }
      want(pack.objects.vat).exists
    })
  })
})
