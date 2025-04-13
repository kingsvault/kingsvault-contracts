// This setup uses Hardhat Ignition to manage smart contract deployments.
// Learn more about it at https://hardhat.org/ignition

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import hre from "hardhat";


const TestUsdt = buildModule("TestUsdt", (m) => {
  const name = "USDT 18";
  const symbol = "USDT";
  const decimals = 18;
  const initialSupply = hre.ethers.parseUnits("100000000", decimals);


  const usdt = m.contract(
    "TestErc20",
    [name, symbol, decimals, initialSupply],
    {}
  );
  console.log("usdt", usdt)

  return { usdt, };
});

export default TestUsdt;
