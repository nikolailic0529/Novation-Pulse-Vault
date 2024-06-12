import * as hre from "hardhat";
import { PayoutAgent } from "../types/ethers-contracts/PayoutAgent";
import { PayoutAgent__factory } from "../types/ethers-contracts/factories/PayoutAgent__factory";
import { MocStrategy } from "../types/ethers-contracts/MocStrategy";
import { MocStrategy__factory } from "../types/ethers-contracts/factories/MocStrategy__factory";
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
  const deployer = (await ethers.getSigners()).filter(
    (account) =>
      account.address === "0x7B9e671B6cd10FD782Bdb982D40ffc0435C3C030"
  )[0];

  console.log("Deploying contracts with the account:", deployer.address);

  const beforeBalance = await deployer.getBalance();
  console.log("Account balance:", (await deployer.getBalance()).toString());

  const mainnet = process.env.NETWORK == "mainnet" ? true : false;
  const url = mainnet ? process.env.URL_MAIN : process.env.URL_TEST;
  const payoutAddress = mainnet
    ? address.mainnet.payoutAgent
    : address.testnet.payoutAgent;
  const vfxAddress = mainnet ? address.mainnet.vfx : address.testnet.vfx;
  const assetAddress = mainnet ? address.mainnet.usdt : address.testnet.usdt;

  const payoutFactory: PayoutAgent__factory = new PayoutAgent__factory(
    deployer
  );
  let payout: PayoutAgent = payoutFactory
    .attach(payoutAddress)
    .connect(deployer);
  if ("Redeploy" && true) {
    payout = await payoutFactory.deploy(assetAddress, vfxAddress);
  }
  console.log("PayoutAgent: ", payout.address);

  const afterBalance = await deployer.getBalance();
  console.log("Deployed cost:", beforeBalance.sub(afterBalance).toString());
}

deploy()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
