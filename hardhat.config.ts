import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

import "@nomicfoundation/hardhat-ignition-ethers";
import "@openzeppelin/hardhat-upgrades";
import "hardhat-contract-sizer";
import "@nomicfoundation/hardhat-verify";

import dotenv from "dotenv";
dotenv.config();



const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.28",
    settings: {
      //viaIR: true,
      optimizer: {
        enabled: true,
        runs: 200,
      },
      evmVersion: "cancun",
    },
  },

  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  mocha: {
    timeout: 40000,
  },

  contractSizer: {
    alphaSort: true,
    runOnCompile: true,
    disambiguatePaths: false,
  },

  networks: {
    hardhat: {
    },
    mainnet: {
      chainId: 1,
      url: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_API_KEY}`,
      accounts: {
        mnemonic: process.env.MNEMONIC,
      },
    },
    sepolia: {
      chainId: 11155111,
      url: `https://eth-sepolia.alchemyapi.io/v2/${process.env.ALCHEMY_API_KEY}`,
      accounts: {
        mnemonic: process.env.MNEMONIC,
      },
    },

    bsc: {
      chainId: 56,
      url: "https://bsc-dataseed.binance.org/",
      accounts: {
        mnemonic: process.env.MNEMONIC,
      },
    },
    bscTestnet: {
      chainId: 97,
      url: "https://data-seed-prebsc-1-s1.binance.org:8545", // RPC для тестовой сети BSC
      accounts: {
        mnemonic: process.env.MNEMONIC,
      },
    },
  },

  etherscan: {
    apiKey: {
      // @ts-expect-error
      mainnet: process.env.ETHERSCAN_API_KEY,
      // @ts-expect-error
      sepolia: process.env.ETHERSCAN_API_KEY,
      // @ts-expect-error
      bsc: process.env.BSCSCAN_API_KEY,
      // @ts-expect-error
      bscTestnet: process.env.BSCSCAN_API_KEY,
    },
  },

  sourcify: {
    // Disabled by default
    // Doesn't need an API key
    enabled: true,
  },
};

export default config;
