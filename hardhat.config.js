require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

const { BSC_TESTNET_RPC, PRIVATE_KEY } = process.env;

module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.20",
        settings: { optimizer: { enabled: true, runs: 200 } },
      },
      {
        version: "0.8.22",
        settings: { optimizer: { enabled: true, runs: 200 } },
      },
      {
        version: "0.8.28",
        settings: { optimizer: { enabled: true, runs: 200 } },
      },
    ],
  },
  networks: {
    hardhat: {
      chainId: 1337,
      accounts: {
        count: 20,
        accountsBalance: "10000000000000000000000", // 10,000 ETH (wei)
      },
    },

    localhost: { url: "http://127.0.0.1:8545" },

    bscTestnet: {
      url: BSC_TESTNET_RPC,
      accounts: PRIVATE_KEY ? [PRIVATE_KEY] : [],
      chainId: 97,
    },
  },

  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
    customChains: [
      {
        network: "bscTestnet",
        chainId: 97,
        urls: {
          apiURL: "https://api-testnet.bscscan.com/api",
          browserURL: "https://testnet.bscscan.com",
        },
      },
    ],
  },
};
