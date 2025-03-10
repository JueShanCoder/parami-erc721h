import { ethers } from "hardhat";
import { expect } from "chai";
import { HNFTGovernanceToken, HNFTGovernance, EIP5489ForInfluenceMining} from "../typechain/";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

describe("HNFTGovernance", () => {
  let hnftGovernance: HNFTGovernance;
  let hnftGovernanceToken: HNFTGovernanceToken;
  let hnftContract: EIP5489ForInfluenceMining;
  let owner: SignerWithAddress;
  let addr1: SignerWithAddress;

  beforeEach(async () => {
    [owner, addr1] = await ethers.getSigners();

    const EIP5489ForInfluenceMining = await ethers.getContractFactory("EIP5489ForInfluenceMining");
    hnftContract = await EIP5489ForInfluenceMining.deploy();
    await hnftContract.deployed();

    hnftContract.mint("https://app.parami.io/hnft/ethereum/0x1/1", 0);

    const HNFTGovernanceToken = await ethers.getContractFactory("HNFTGovernanceToken");
    hnftGovernanceToken = await HNFTGovernanceToken.deploy("AD3 Token", "AD3");
    await hnftGovernanceToken.deployed();

    const HNFTGovernance = await ethers.getContractFactory("HNFTGovernance");
    hnftGovernance = await HNFTGovernance.deploy();
    await hnftGovernance.deployed();
  });

  it("should allow NFT owner to govern with token", async () => {
    const tokenId = 1;
    await hnftGovernance.connect(owner).governWith(hnftContract.address, tokenId, hnftGovernanceToken.address);

    expect(await hnftGovernance.getGovernanceToken(hnftContract.address, tokenId)).to.equal(hnftGovernanceToken.address);
  });

  it("should not allow non-owner to govern with token", async () => {
    const tokenId = 1;
    await expect(
      hnftGovernance.connect(addr1).governWith(hnftContract.address, tokenId, hnftGovernanceToken.address)
    ).to.be.revertedWith("Only the NFT owner can governed");
  });

  it("should emit event when NFT is governed", async () => {
    const tokenId = 1;

    await expect(hnftGovernance.connect(owner).governWith(hnftContract.address, tokenId, hnftGovernanceToken.address))
      .to.emit(hnftGovernance, "Governance")
      .withArgs(tokenId, hnftGovernanceToken.address);
  });
  
});
