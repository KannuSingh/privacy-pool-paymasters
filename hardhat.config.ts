import type { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox-viem";
import "@nomicfoundation/hardhat-foundry"; 

const config: HardhatUserConfig = {
    solidity: {
        version: "0.8.28",
        settings: {
            optimizer: {
                enabled: true,
                runs: 10000,
            },
            evmVersion: "cancun",
        },
    },
    paths: {
        sources: "src/contracts/",
        root: ".",
    },
};

export default config;
