import * as hre from "hardhat";
import { MocVault } from "../types/ethers-contracts/MocVault";
import { MocVault__factory } from "../types/ethers-contracts/factories/MocVault__factory";
import address from "../address";

require("dotenv").config();

const { ethers } = hre;

const toEther = (val: any) => {
  return ethers.utils.formatEther(val);
};

const toWei = (val: any, unit = 18) => {
  return ethers.utils.parseUnits(val, unit);
};

async function deploy() {
  console.log(new Date().toLocaleString());

  // const deployer = (await ethers.getSigners()).filter(account => account.address === "0x32f1C25148DeCbdBe69E1cc2F87E0237BC34b700")[0];
  // const deployer = (await ethers.getSigners()).filter(account => account.address === "0x12D16f3A335dfdB575FacE8e3ae6954a1C0e24f1")[0];
  // const deployer = (await ethers.getSigners()).filter(account => account.address === "0x647BB910944165D14b961985c28b06b08cA47f77")[0];

  const deployer = (await ethers.getSigners()).filter(
    (account) =>
      account.address === "0x12D16f3A335dfdB575FacE8e3ae6954a1C0e24f1"
  )[0];

  console.log("Deploying contracts with the account:", deployer.address);

  const beforeBalance = await deployer.getBalance();
  console.log("Account balance:", (await deployer.getBalance()).toString());

  const mainnet = process.env.NETWORK == "mainnet" ? true : false;
  const mocVaultAddress = mainnet ? address.mainnet.mocVault : address.testnet.mocVault;
  const assetAddress = mainnet ? address.mainnet.usdt : address.testnet.usdt;

  const mocVaultFactory: MocVault__factory = new MocVault__factory(deployer);
  let mocVault: MocVault = mocVaultFactory.attach(mocVaultAddress).connect(deployer);
  if ("Redeploy" && true) {
    mocVault = await mocVaultFactory.deploy(assetAddress);
  }
  console.log("MocVault: ", mocVault.address);

  const afterBalance = await deployer.getBalance();
  console.log("Deployed cost:", beforeBalance.sub(afterBalance).toString());
}

deploy()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
