require("@nomiclabs/hardhat-ethers");
require("dotenv").config();

module.exports = {
   solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    hardhat: {},
    bscTestnet: {
      url: process.env.BSC_TESTNET_RPC_URL,
      accounts: [process.env.PRIVATE_KEY],
      chainId: 97
    },
    bscMainnet: {
      url: process.env.BSC_MAINNET_RPC_URL,
      accounts: [process.env.PRIVATE_KEY],
      chainId: 56
    }
  },
};