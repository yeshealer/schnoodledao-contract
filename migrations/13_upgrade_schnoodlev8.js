// migrations/13_upgrade_schnoodlev8.js

module.exports = async function (deployer, network, accounts) {
  if (network == 'develop') return;
  const { upgrade } = require('../scripts/contracts.js');
  await upgrade(deployer, network, 'SchnoodleV1', 'SchnoodleV8');
};