import * as hre from 'hardhat';
import { TefiVault } from '../types/ethers-contracts/TefiVault';
import { TefiVault__factory } from '../types/ethers-contracts/factories/TefiVault__factory';
import { MocStrategy } from '../types/ethers-contracts/MocStrategy';
import { MocStrategy__factory } from '../types/ethers-contracts/factories/MocStrategy__factory';
import address from '../address';

require("dotenv").config();

const { ethers } = hre;

const toEther = (val: any) => {
    return ethers.utils.formatEther(val);
}

const toWei = (val: any, unit = 18) => {
    return ethers.utils.parseUnits(val, unit);
}

async function deploy() {
    console.log((new Date()).toLocaleString());
    
    // const deployer = (await ethers.getSigners()).filter(account => account.address === "0x32f1C25148DeCbdBe69E1cc2F87E0237BC34b700")[0];
    const deployer = (await ethers.getSigners()).filter(account => account.address === "0x12D16f3A335dfdB575FacE8e3ae6954a1C0e24f1")[0];
    
    console.log(
        "Deploying contracts with the account:",
        deployer.address
    );

    const beforeBalance = await deployer.getBalance();
    console.log("Account balance:", (await deployer.getBalance()).toString());

    const mainnet = process.env.NETWORK == "mainnet" ? true : false;
    const url = mainnet ? process.env.URL_MAIN : process.env.URL_TEST;
    const curBlock = await ethers.getDefaultProvider(url).getBlockNumber();
    const vaultAddress = mainnet ? address.mainnet.vault : address.testnet.vault;
    const strategyAddress = mainnet ? address.mainnet.strategy : address.testnet.strategy;
    const assetAddress = mainnet ? address.mainnet.usdt : address.testnet.usdt;
    const payoutAddress = mainnet ? address.mainnet.payoutAgent : address.testnet.payoutAgent;

    const strategyFactory: MocStrategy__factory = new MocStrategy__factory(deployer);
    let strategy: MocStrategy = strategyFactory.attach(strategyAddress).connect(deployer);
    if ("Redeploy" && false) {
        strategy = await strategyFactory.deploy(assetAddress);
    }
    console.log('MocStrategy: ', strategy.address);
    
    const vaultFactory: TefiVault__factory = new TefiVault__factory(deployer);
    let vault: TefiVault = vaultFactory.attach(vaultAddress).connect(deployer);
    if ("Redeploy" && true) {
        vault = await vaultFactory.deploy("0x12D16f3A335dfdB575FacE8e3ae6954a1C0e24f1", assetAddress, payoutAddress);
    }
    console.log('TefiVault: ', vault.address);

    await strategy.setVault(vault.address);

    const afterBalance = await deployer.getBalance();
    console.log(
        "Deployed cost:",
         (beforeBalance.sub(afterBalance)).toString()
    );
}

deploy()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    })