// test/mavro.referral.test.js
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");

const parse = (v) => ethers.parseEther(v.toString());

async function deployFixture() {
  const [deployer, user1, user2, user3, user4, user5, user6, user7, user8] =
    await ethers.getSigners();

  // USDT
  const USDT = await ethers.getContractFactory("TestUSDT");
  const usdt = await USDT.deploy(deployer.address);
  await usdt.waitForDeployment();

  const transferAmount = parse(1000000);
  await usdt.transfer(user1.address, transferAmount);
  await usdt.transfer(user2.address, transferAmount);
  await usdt.transfer(user3.address, transferAmount);
  await usdt.transfer(user4.address, transferAmount);
  await usdt.transfer(user5.address, transferAmount);
  await usdt.transfer(user6.address, transferAmount);
  await usdt.transfer(user7.address, transferAmount);
  await usdt.transfer(user8.address, transferAmount);

  // MAVRO
  const MAVRO = await ethers.getContractFactory("MavroCoin");
  const mavro = await MAVRO.deploy(deployer.address);
  await mavro.waitForDeployment();

  // NFT
  const NFT = await ethers.getContractFactory("NodeNFT");
  const nft = await NFT.deploy();
  await nft.waitForDeployment();

  // Referral
  const Referral = await ethers.getContractFactory("MavroNewReferralsSystem");
  const referral = await Referral.deploy(
    mavro.target,
    usdt.target,
    1765435210,
    565
  );
  await referral.waitForDeployment();

  // Node
  const Node = await ethers.getContractFactory("MavroNodeSale");
  const node = await Node.deploy(
    usdt.target,
    nft.target,
    referral.target,
    deployer.address
  );
  await node.waitForDeployment();

  // Roles
  const MINTER_ROLE = await nft.MINTER_ROLE();
  await nft.grantRole(MINTER_ROLE, node.target);

  const RECORD_ROLE = await referral.RECORDER_ROLE();
  await referral.grantRole(RECORD_ROLE, node.target);

  // Approvals
  const approveAmount = parse(10000000);
  const users = [user1, user2, user3, user4, user5, user6, user7, user8];
  for (const u of users) {
    await usdt.connect(u).approve(node.target, approveAmount);
  }

  await referral.connect(deployer).updateMigrationDuration(1);
  await referral.connect(deployer).finalizeMigration();

  return {
    deployer,
    user1,
    user2,
    user3,
    user4,
    user5,
    user6,
    user7,
    user8,
    usdt,
    mavro,
    nft,
    referral,
    node,
  };
}

describe("Mavro referrals + NodeSale", function () {
  it("User1 can buy a node with deployer as referrer", async function () {
    const { deployer, user1, node, referral } = await loadFixture(
      deployFixture
    );

    await node.connect(user1).buyNodes(1, deployer.address);

    // Example assertions (adapt to your contract):
    const refInfo = await referral.referrals(user1.address);
    expect(refInfo.referrer).to.equal(deployer.address);

    const totalNodesUser1 = await node.nodeCountOfAUser(user1.address); // or your getter
    expect(totalNodesUser1).to.equal(1n);
  });

  it("user 2 buy 20 nodes with user1 referer", async function () {
    const { user1, user2, node, referral } = await loadFixture(deployFixture);

    await node.connect(user2).buyNodes(20, user1.address);

    // Example assertions (adapt to your contract):
    const refInfo = await referral.referrals(user2.address);
    expect(refInfo.referrer).to.equal(user1.address);

    const myRank = await referral.checkMyRank(user1.address);
    console.log("user1 rank after 20 nodes refered:", myRank);

    const totalNodesUser2 = await node.nodeCountOfAUser(user2.address); // or your getter
    expect(totalNodesUser2).to.equal(20n);
  });

  it("user 3 buy 10 nodes with user1 referer", async function () {
    const { user1, user3, node, referral } = await loadFixture(deployFixture);

    await node.connect(user3).buyNodes(10, user1.address);

    // Example assertions (adapt to your contract):
    const refInfo = await referral.referrals(user3.address);
    expect(refInfo.referrer).to.equal(user1.address);

    const myRank = await referral.checkMyRank(user1.address);
    console.log("user1 rank after 10 nodes refered:", myRank);

    const totalNodesUser3 = await node.nodeCountOfAUser(user3.address); // or your getter
    expect(totalNodesUser3).to.equal(10n);
  });

  it("user 4 buy 10 nodes with user1 referer", async function () {
    const { user1, user4, node, referral } = await loadFixture(deployFixture);

    await node.connect(user4).buyNodes(10, user1.address);

    // Example assertions (adapt to your contract):
    const refInfo = await referral.referrals(user4.address);
    expect(refInfo.referrer).to.equal(user1.address);

    const myRank = await referral.checkMyRank(user1.address);
    console.log("user1 rank after 10 nodes refered:", myRank);

    const totalNodesUser4 = await node.nodeCountOfAUser(user4.address); // or your getter
    expect(totalNodesUser4).to.equal(10n);
  });

  it("user 5 buy 15 nodes with user1 referer", async function () {
    const { user1, user5, node, referral } = await loadFixture(deployFixture);

    await node.connect(user5).buyNodes(15, user1.address);

    // Example assertions (adapt to your contract):
    const refInfo = await referral.referrals(user5.address);
    expect(refInfo.referrer).to.equal(user1.address);

    const myRank = await referral.checkMyRank(user1.address);
    console.log("user1 rank after 15 nodes refered:", myRank);

    const totalNodesUser5 = await node.nodeCountOfAUser(user5.address); // or your getter
    expect(totalNodesUser5).to.equal(15n);
  });

  it("user5 transfer 5 nodes to user2 to check user1 Rank", async function () {
    const { user1, user2, user5, node, referral } = await loadFixture(
      deployFixture
    );

    const activeNodesBefore = await node.getMyActiveNodes(user5.address);
    console.log(
      "user5 active nodes before transfer:",
      activeNodesBefore.length
    );
    for (let index = 0; index < 5; index++) {
      const nodeId = activeNodesBefore[index];
      await node.connect(user5).transferNode(nodeId, user2.address);
    }

    const activeNodesAfter = await node.getMyActiveNodes(user5.address);
    console.log("user5 active nodes before transfer:", activeNodesAfter.length);
    // Example assertions (adapt to your contract):
    const totalNodesUser2 = await node.nodeCountOfAUser(user2.address); // or your getter
    expect(totalNodesUser2).to.equal(25n);

    const myRank = await referral.checkMyRank(user1.address);
    console.log("user1 rank after 15 nodes refered:", myRank);
  });
});
