export const address = {
    mainnet: {
        bnb: "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
        pcsRouter: "0x10ED43C718714eb63d5aA57B78B54704E256024E",
        factory: "0x72d892a36EC529cB2b81430E8d73364aB78277f0",
        router: "0x0Fa0544003C3Ad35806d22774ee64B7F6b56589b",
        swap: "0x2085B84912531B126f1C92cd70A71381713f0795",
        pcsAgent: "0xfeB4e72349d19baE6842B74680ad75C21c1190f3",
        feeFactory: "0x369619A38099edca45890e4B7Ad5667735B0B26E",
        feeFactoryV1: "0xe75F5434AF200AE26eA266fB3C1AB04fc2b64ac3",
        airdrop: "0xcAD7FbFBd60Fd1285E6742a32700b09d194b4893",
        launchpad: "0xf5416ee250DbC1c19f3e0c19951e8c124376613A",
        //launchpad: "0x0f56E38447DDd2F9e02fE07F56Ec99AdF1E981F7",
        //launchpad: "0x5F3eFaf0d8bF251a28db32D6e77EF2b588ce3AE2", // It has the problem unchecking canceled
        launchpadV1: "0x39eFcd7f93051409c16C4A0df248CDeFB879A628",
        price: "0x9A1CE07b43F9E96A9bdF76c412A7005799b795Ab",
        tokens: {
            tefi: "0xD23a8017B014cB3C461a80D1ED9EC8164c3f7A77",
            tefiLP: "0x509500A4d68E84dcea864006eadc7D568aF45d16",
            vault: "0xe06f46AFD251B06152B478d8eE3aCea534063994",
            vaultDividend: "0x1aA67E1B576Ffc0Ed12A224F84573C9011cB8841",
            vaultLP: "0x48667C2D282eEf9266Db2b69Cfa97c185c97A5Ab",
            dyor: "0x10051147418C42218986CeDD0aDC266441F8a14f",
            dyorLP: "0xD51729A6FdC27566ccEFF1C166eC3a450F2E1CD5",
            vb: "0x5CEe1D156C5D8b8d04aD2661F498E1706619Bb22",
            vbLP: "0xBf97a6c877955d43639EAEd147427aB81a13A06D",
            mkf: "0xc8faF90F8fcA363E261d8d1892A31a636aA1ef5C",
        },
        ditributors: {
            tefi: "0xAb894c60d57d6a6f340A2c7F12Ad5a59fAAbCdD9",
            vault: "0x326E3f2C9e20947F54851e8aF30EF8A9b8406E3C",
            dyor: "0xbB39BD00aDb038BD8aa038a59d8F3553E283A04D",
            vb: "0x3f3eb485Edea222919C9e358417120D8b7d3A799",
            mkf: "0x51D94E896526E6E7679679aC30340AaCcBC0067f"
        },
        farm: {
            strategy: "0x656a0c3aC9900f74305FcC0338DCaD8A8DF4f9BF",
            vault: "0x7C19BB91c68405CAC0A77727eCe7abF516E5af5D",
            asset: "0x55d398326f99059fF775485246999027B3197955"
        }
    },
    mainnetTest: {
        bnb: "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
        pcsRouter: "0x10ED43C718714eb63d5aA57B78B54704E256024E",
        factory: "0x9958a344e1c5B2BbD6d36e086146fE7211f30d54",
        router: "0xd4E866F09d64382186d88ffd8714619A9f1B8524",
        swap: "0x355f7896d30c02b8E6db88A61B5D9B754cfE7253",
        pcsAgent: "0x2853263075e6fA0275b9c7b86E7C5874fCEd2680",
        feeFactory: "0x63030C087b824DF6828FEf5b4360d3314f63cE62",
        vault: "0x3A047c7318EA39758DAdDD63742A3eA98f156dba",
        vaultWithDividend: "0xb2c12e3978e25051710F6bfe2e7374bFf7000Ec6",
        launchpad: "0x70AE98CD81A79b1196389940569C87ad5eCC89F7",
        tokens: {
            vault: "0xe06f46AFD251B06152B478d8eE3aCea534063994",
            tefi: "0xD23a8017B014cB3C461a80D1ED9EC8164c3f7A77",
            moc1: "0x8E1CB690a0fB0A7Bc059796185Aa2F477336D1e5",
            moc2: "0xc9F8440E62A50a8be009b3cCa2B279be62d7679D",
            moc3: "0xa4BbEed7003D03d844BC0ecE86b110dC954759c5",
        },
        distributors: {
            tefi: "0x0c8A4Cfd0c5cdecdA60d0F11935405890860B133",
            dist1: "0x546620ee2605106c3376C6A4d5E74BA04961c667",
            dist2: "0x9785Cee062b877523DAeEc8d07D2d3B7Af3DE22a",
            dist3: "0x2c50666Ec6525AaFA9787a4cb23a9EE8e24F0FaB",
            vault: "0x4E2935699509844aE6765FF6856359CE1C08031e",

        }
    },
    testnet: {
        bnb: "0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd",
        pcsRouter: "0xD99D1c33F9fC3444f8101754aBC46c52416550D1",
        factory: "0x7E8EB04A303435fD57f41b63c3A4885B245C0Bd3",
        router: "0x291d6B7A0c93c8C73BAB5f0D9cDcEb905cc0F428",
        swap: "0x681dCD13e55C295AAD0141952bF94cF785A5179C",
        pcsAgent: "0x15d5D707f58E6CE695FeF1ed65A0a9FE10241A4B",
        feeFactory: "0x8329911Ce88f67E794568c9f81BBF9C742BcC949",
        airdrop: "0xe75F5434AF200AE26eA266fB3C1AB04fc2b64ac3",
        launchpad: "0xe9AEb1770c1A341Efa19f04634C21729c7EA4FFe",
        price: "0x39eFcd7f93051409c16C4A0df248CDeFB879A628",
        distributors: {
            tefi: "0xe8E9be684d97eb7bd53c245eCcD3D1236Ad8c039",
            cft: "0xf08E66f833f3FC35047b3ab2B3c6907b3cC4E17D",
            dist1: "0xe8E9be684d97eb7bd53c245eCcD3D1236Ad8c039",
            dist2: "0xAe2Bf9D2c1d7d0cbdF290828D6B6ecE95700C925",
            dist3: "0x9785Cee062b877523DAeEc8d07D2d3B7Af3DE22a",
        },
        tokens: {
            vault: "0x714dd6904EDF4d47808a6c7e36c569959d2f95cF",
            tefi: "0xd7d7F4313A6F098c200aFc4f313DC84301D55Cd1",
            cft: "0xA81bD898039AE1f6B783Ed73c2dC20c5Da94383b",
            moc1: "0xd7d7F4313A6F098c200aFc4f313DC84301D55Cd1",
            moc2: "0x2051a4816515e60767B612081C9Ba8134C5A418F",
            moc3: "0x43916De3b9c0b9A2aCdE5D74bF564dD9b6F70649",
            moc4: "0x4D6de0D467c9729127D320fe7982BFCaBE19fa86",
            moc5: "0xb2c12e3978e25051710F6bfe2e7374bFf7000Ec6",
        },
        farm: {
            strategy: "0x656a0c3aC9900f74305FcC0338DCaD8A8DF4f9BF",
            vault: "0x02b3a54Ff83c0FeBD611D046ca4fF7716465b32d",
            asset: "0xd7d7F4313A6F098c200aFc4f313DC84301D55Cd1"
        }
    },
    testnetAudit: {
        bnb: "0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd",
        pcsRouter: "0xD99D1c33F9fC3444f8101754aBC46c52416550D1",
        factory: "0x7E8EB04A303435fD57f41b63c3A4885B245C0Bd3",
        router: "0x1F50f100772B4E32Bd446e9479A031351f307785",
        swap: "0x5a098e3336413B2B14aef5DA7409D23504D3b4b6",
        pcsAgent: "0x15d5D707f58E6CE695FeF1ed65A0a9FE10241A4B",
        feeFactory: "0x8329911Ce88f67E794568c9f81BBF9C742BcC949",
        vault: "0x3cF1471eCA18b8Afe443e94F829e41c12fAc3507",
        distributors: {
            audit: "0x4e0DFA07545327f65626f25e8de05AE814617ed5"
        },
        tokens: {
            tefi: "0xd7d7F4313A6F098c200aFc4f313DC84301D55Cd1",
        }
    }
}

export default address;