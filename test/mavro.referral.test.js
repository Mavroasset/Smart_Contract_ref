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

  //transfer mavro to referral contract
  const mavroTransferAmount = parse(10000000);
  await mavro.transfer(referral.target, mavroTransferAmount);

  // Node
  const Node = await ethers.getContractFactory("MavroNodeSale");
  const node = await Node.deploy(
    usdt.target,
    nft.target,
    referral.target,
    deployer.address
  );
  await node.waitForDeployment();

  //Staking
  const Staking = await ethers.getContractFactory("MavroStaking");
  const staking = await Staking.deploy(mavro.target, referral.target);
  await staking.waitForDeployment();

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

  //refrral updates

  await referral.connect(deployer).updateMigrationDuration(1);
  await referral.connect(deployer).finalizeMigration();
  await referral
    .connect(deployer)
    .updateContracts(usdt.target, mavro.target, node.target, staking.target);

  let nodeReq = 10;
  for (let index = 0; index < 6; index++) {
    await referral
      .connect(deployer)
      .updateRankRequirements(index, nodeReq, 5000, 0);

    nodeReq = nodeReq + 2;
  }

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
  it("full flow: user2/3/4/5 buy, then user5 transfers 5 nodes to user2 and rank is updated", async function () {
    const {
      deployer,
      user1,
      user2,
      user3,
      user4,
      user5,
      user6,
      user7,
      user8,
      node,
      referral,
    } = await loadFixture(deployFixture);

    // 1) Buys
    await node.connect(user1).buyNodes(10, deployer.address);
    await node.connect(user2).buyNodes(10, user1.address);
    await node.connect(user3).buyNodes(10, user2.address);
    await node.connect(user4).buyNodes(5, user1.address);
    await node.connect(user5).buyNodes(16, user4.address);
    await node.connect(user6).buyNodes(5, user2.address);

    // 2) Basic sanity checks after buys
    // const nodesUser2Before = await node.nodeCountOfAUser(user2.address);
    // const nodesUser3 = await node.nodeCountOfAUser(user3.address);
    // const nodesUser4 = await node.nodeCountOfAUser(user4.address);
    // const nodesUser5Before = await node.nodeCountOfAUser(user5.address);

    // expect(nodesUser2Before).to.equal(20n);
    // expect(nodesUser3).to.equal(10n);
    // expect(nodesUser4).to.equal(10n);
    // expect(nodesUser5Before).to.equal(15n);

    // 3) user5 transfers 5 active nodes to user2
    // const activeNodesBefore = await node.getMyActiveNodes(user5.address);
    // console.log(
    //   "user5 active nodes BEFORE transfer:",
    //   activeNodesBefore.length
    // );

    // make sure user5 actually has enough nodes for the test
    // expect(activeNodesBefore.length).to.be.gte(5);

    // for (let i = 0; i < 5; i++) {
    //   const nodeId = activeNodesBefore[i].nodeId;
    //   await node.connect(user5).transferNode(nodeId, user2.address);
    // }

    // const activeNodesAfter = await node.getMyActiveNodes(user5.address);
    // console.log("user5 active nodes AFTER transfer:", activeNodesAfter.length);

    // depending on your logic, this might be "length - 5" if only active count changes
    // expect(activeNodesAfter.length).to.equal(activeNodesBefore.length - 5);

    // 4) Final node counts
    // const nodesUser2After = await node.nodeCountOfAUser(user2.address);
    // const nodesUser5After = await node.nodeCountOfAUser(user5.address);

    // user2 had 20, got 5 more
    // expect(nodesUser2After).to.equal(25n);
    // // user5 had 15, sent 5
    // expect(nodesUser5After).to.equal(10n);

    // 5) Rank check for user1
    await node.connect(user2).buyNodes(5, user1.address);

    const myRank = await referral.checkMyRank(user1.address);
    console.log("user1 rank:", myRank.toString());

    for (let index = 2; index <= myRank; index++) {
      const isPoolUser = await referral.isPoolParticipant(index, user1.address);
      console.log(`user1 is pool participant for rank ${index}:`, isPoolUser);
    }

    // await node.connect(user2).buyNodes(5, user1.address);
    // await node.connect(user7).buyNodes(15, user5.address);

    // const nodesUser2AfterNewBuy = await node.nodeCountOfAUser(user2.address);

    // console.log(
    //   "user2 nodes after buying 5 more:",
    //   nodesUser2AfterNewBuy.toString()
    // );

    const teamNodesUser2 = await referral.teamNodeCount(user2.address);
    console.log("user2 team nodes:", teamNodesUser2.toString());

    const teamNodesUser4 = await referral.teamNodeCount(user4.address);
    console.log("user4 team nodes:", teamNodesUser4.toString());

    // const myRank2 = await referral.checkMyRank(user1.address);
    // console.log("user1 rank after user2 buy 5 more nodes:", myRank2.toString());

    // If you know the numeric value of the expected rank enum, assert it here:
    // expect(myRank).to.equal(<EXPECTED_RANK_ENUM_VALUE>);

    //add new pool and check details
    // const poolCount = await referral.totalPools();
    // console.log("Total pools before adding new one:", poolCount.toString());
    // await referral.connect(deployer).addPool(parse(500000), 0, 0, 0, 0, 0, 0);

    // const poolCountAfter = await referral.totalPools();
    // console.log("Total pools after adding new one:", poolCountAfter.toString());
    // for (let i = 0; i < poolCountAfter; i++) {
    //   const poolDetails = await referral.pools(i);
    //   console.log(`Pool ${i} details:`, poolDetails);
    // }
  });
});
