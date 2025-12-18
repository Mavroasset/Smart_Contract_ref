// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./BokkyPooBahsDateTimeLibrary.sol";

interface NodeSale {
    function addressToID(address user) external view returns (string memory);

    function getCoFounderCount() external view returns (uint256);

    function maxCoFounders() external view returns (uint256);
}

interface Staking {
    function getUserTotalStakeAmount(
        address _user
    ) external view returns (uint256);
}

contract MavroNewReferralsSystem is Ownable, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant RECORDER_ROLE = keccak256("RECORDER_ROLE");
    bytes32 public constant SNAPSHOT_ROLE = keccak256("SNAPSHOT_ROLE");

    enum Rank {
        Member,
        Councilor,
        AlphaAmbassador,
        Country,
        Regional,
        Global
    }

    IERC20 public rewardToken;
    IERC20 public cashRewardToken;
    address public nodeSaleContract;
    address public stakingContract;

    uint256 public constant MAX_YEAR_FOR_REWARD = 7;
    uint256 public FIRST_AND_2ND_YEAR_DAILY_REWARD = 2260000 * 10 ** 18;
    uint256 public THIRD_AND_4TH_YEAR_DAILY_REWARD = 1130000 * 10 ** 18;
    uint256 public FIFTH_YEAR_DAILY_REWARD = 753400 * 10 ** 18;
    uint256 public SIXTH_YEAR_DAILY_REWARD = 753400 * 10 ** 18;
    uint256 public SEVENTH_YEAR_DAILY_REWARD = 753400 * 10 ** 18;

    // level cash rewards
    uint256 public firstLevelCashReward = 700;
    uint256 public secondLevelCashReward = 300;
    uint256 public thirdLevelCashReward = 100;

    // level generation rewards
    uint256 public firstLevelReward = 300;
    uint256 public secondLevelReward = 100;
    uint256 public thirdLevelReward = 100;

    uint256 public BASE_DIVIDER = 10000;

    uint256 public time_interval = 365 days;
    uint256 public immutable reward_interval = 1 days;

    uint256 public totalNodesSold;

    uint256 public totalNodeRewardClaimed;

    uint256 public totalReferralRewardClaimed;

    uint256 public totalPools;

    uint256 public claimDay = 25;

    uint256 public coFounderPoolID;

    uint256 public nodeRequiredToLaunch = 500;
    uint256 public time_interva_coFounder = 180 days;

    uint256 public BASE_DECIMALS = 1e18;

    uint256 public migrationTime;
    uint256 public migrationDuration = 3 days;

    uint256 public migrationCutoffDay;
    bool public migrationRewardWindowClosed;

    struct TeamMemberWithNodes {
        string memberId;
        uint256 nodeCount;
    }

    struct UserInfo {
        uint256 nodesOwned;
        uint256 entryTime;
        uint256 lastClaimTime;
        uint256 totalNodeRewardReceived;
        uint256 totalRefRewardReceived;
        uint256 totalCashReceived;
        Rank currentRank;
    }

    struct ReferralInfo {
        address referrer;
        mapping(uint256 => uint256) nodesEachLevel;
        uint256 teamNodes;
        address[] directTeam;
    }

    struct RankRequirements {
        uint256 nodeRequirement;
        uint256 referralPercentage;
        uint256 stakingAmount;
    }

    struct RewardPool {
        uint256 poolId;
        uint256 firstYearAmount;
        uint256 secondYearAmount;
        uint256 thirdYearAmount;
        uint256 fourthYearAmount;
        uint256 fifthYearAmount;
        uint256 sixthYearAmount;
        uint256 seventhYearAmount;
        address[] participants;
        uint256 rewardStartTime;
    }

    struct MigrationInput {
        address user;
        address referrer;
        uint256 teamNode;
        address[] directteam;
        uint256[3] levels;
        uint256 nodesOwned;
        uint256 entryTime;
        uint256 totalCashReceived;
        Rank currentRank;
    }

    struct DailySnapshot {
        uint256 totalNodes;
        uint256 totalReward;
        uint256 rewardPerNode;
    }

    mapping(uint256 => DailySnapshot) public dailySnapshots;
    mapping(address => uint256) public lastNodeClaimedDay;
    mapping(address => uint256) public lastReferralClaimedDay;

    mapping(address => mapping(uint256 => uint256)) public nodesOwnedPerDay;
    mapping(address => mapping(uint256 => uint256[4]))
        public dailyReferralNodesEachLevel;

    uint256[] public usersRequiredForRankReward = [0, 0, 20, 10, 5, 3];

    mapping(uint256 => RewardPool) public pools;
    mapping(Rank => RankRequirements) public rankRequirements;
    mapping(address => Rank) public userRanks;

    mapping(address => UserInfo) public users;
    mapping(address => ReferralInfo) public referrals;
    mapping(address => uint256) public lastNodeRewardClaimedTime;
    mapping(address => uint256) public lastReferralRewardClaimedTime;
    mapping(address => bool) public isCoFounder;
    mapping(address => uint256) public lastRankClaimedTime;
    mapping(address => uint256) public lastCoFounderClaimedTime;
    mapping(address => uint256) public coFounderEntryTime;
    mapping(uint256 => mapping(uint256 => uint256)) public rankRewardPerMonth;
    mapping(address => bool) public hasMigrated;
    mapping(address => bool) public isBlocked;

    mapping(address => uint256) public nodesPurchased;
    mapping(address => uint256) public totalDirectTeamNodes;
    mapping(address => uint256) public maxDirectTeamNodes;
    mapping(address => mapping(address => uint256)) public directLegTeamNodes;
    mapping(uint256 => mapping(address => bool)) public isPoolParticipant;

    uint256 public programStartTime;
    bool public initialized;

    event NodePurchased(address indexed user, uint256 count, address referrer);
    event NodeRewardClaimed(address indexed user, uint256 amount);
    event ReferralRewardClaimed(address indexed user, uint256 amount);
    event ReferralRewardAdded(
        address indexed referrer,
        address indexed user,
        uint256 level,
        uint256 amount
    );

    constructor(
        address _rewardToken,
        address _cashrewardToken,
        uint256 _programStartTime,
        uint256 totalNodes
    ) Ownable(msg.sender) {
        programStartTime = _programStartTime;
        migrationTime = block.timestamp;
        initialized = true;
        totalNodesSold = totalNodes;
        rewardToken = IERC20(_rewardToken);
        cashRewardToken = IERC20(_cashrewardToken);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(RECORDER_ROLE, msg.sender);
        _grantRole(SNAPSHOT_ROLE, msg.sender);

        rankRequirements[Rank.Councilor] = RankRequirements(50, 5000, 0);
        rankRequirements[Rank.AlphaAmbassador] = RankRequirements(100, 5000, 0);
        rankRequirements[Rank.Country] = RankRequirements(
            300,
            5000,
            1000000 ether
        );
        rankRequirements[Rank.Regional] = RankRequirements(
            600,
            5000,
            2000000 ether
        );
        rankRequirements[Rank.Global] = RankRequirements(
            1000,
            5000,
            5000000 ether
        );

        for (uint256 i = totalPools; i <= 6; i++) {
            pools[i] = RewardPool({
                poolId: i,
                firstYearAmount: 0,
                secondYearAmount: 0,
                thirdYearAmount: 0,
                fourthYearAmount: 0,
                fifthYearAmount: 0,
                sixthYearAmount: 0,
                seventhYearAmount: 0,
                participants: new address[](0),
                rewardStartTime: 0
            });
            totalPools++;
        }

        //recordDailyReward();
    }

    function recordReferral(
        address user,
        uint256 nodeCount,
        address referrer,
        uint256 _amount
    ) external onlyRole(RECORDER_ROLE) {
        require(migrationRewardWindowClosed, "Currently Unavailable");

        UserInfo storage userInfo = users[user];

        if (userInfo.entryTime == 0 && referrals[user].referrer == address(0)) {
            userInfo.entryTime = block.timestamp;
            _setReferrer(user, referrer);
        }

        totalNodesSold += nodeCount;

        userInfo.nodesOwned += nodeCount;

        nodesPurchased[user] += nodeCount;

        uint256 day = (block.timestamp - programStartTime) / reward_interval;
        dailySnapshots[day].totalNodes = totalNodesSold;
        nodesOwnedPerDay[user][day] = userInfo.nodesOwned;

        if (lastNodeClaimedDay[user] == 0) lastNodeClaimedDay[user] = day;
        if (lastReferralClaimedDay[referrer] == 0 && referrer != address(0)) {
            lastReferralClaimedDay[referrer] = day;
        }

        address current = referrer;
        address leg = user;

        while (current != address(0)) {
            // total purchase-driven downline
            referrals[current].teamNodes += nodeCount;

            // purchase-driven leg score (NOT affected by transfers)
            uint256 newLeg = directLegTeamNodes[current][leg] + nodeCount;
            directLegTeamNodes[current][leg] = newLeg;

            totalDirectTeamNodes[current] += nodeCount;
            if (newLeg > maxDirectTeamNodes[current]) {
                maxDirectTeamNodes[current] = newLeg;
            }

            leg = current;
            current = referrals[current].referrer;
        }

        _distributeCashReferralRewards(user, _amount, nodeCount);

        _updateRank(referrer);

        emit NodePurchased(user, nodeCount, referrer);
    }

    function recordNodeTransfer(
        address from,
        address to,
        uint256 nodeCount
    ) external onlyRole(RECORDER_ROLE) {
        require(migrationRewardWindowClosed, "Currently Unavailable");
        require(users[from].nodesOwned >= nodeCount, "Not enough node");

        UserInfo storage receiverInfo = users[to];

        if (receiverInfo.entryTime == 0) {
            receiverInfo.entryTime = block.timestamp;
        }
        users[from].nodesOwned -= nodeCount;
        users[to].nodesOwned += nodeCount;

        //snapshot part
        uint256 day = (block.timestamp - programStartTime) / reward_interval;

        nodesOwnedPerDay[from][day] = users[from].nodesOwned;
        nodesOwnedPerDay[to][day] = users[to].nodesOwned;
    }

    function addCoFounder(address _user) external onlyRole(RECORDER_ROLE) {
        require(_user != address(0), "Invalid User");
        require(migrationRewardWindowClosed, "Currently Unavailable");
        isCoFounder[_user] = true;
        coFounderEntryTime[_user] = block.timestamp;
    }

    function claimMyNodeRewards() external nonReentrant {
        require(block.timestamp >= programStartTime, "Not started yet");
        _updateRank(msg.sender);

        uint256 today = (block.timestamp - programStartTime) / reward_interval;
        uint256 rewards;
        if (!migrationRewardWindowClosed) {
            require(
                block.timestamp <= migrationTime + migrationDuration,
                "Claim window expired"
            );
            rewards = _calculateNodeRewards(msg.sender);
            require(rewards > 0, "No rewards to claim");

            lastNodeClaimedDay[msg.sender] = today;
            lastNodeRewardClaimedTime[msg.sender] = block.timestamp;

            nodesOwnedPerDay[msg.sender][today] = users[msg.sender].nodesOwned;
        } else {
            if (lastNodeClaimedDay[msg.sender] == 0) {
                lastNodeClaimedDay[msg.sender] = migrationCutoffDay;
                nodesOwnedPerDay[msg.sender][migrationCutoffDay] = users[
                    msg.sender
                ].nodesOwned;
            }
            uint256 timePassed = block.timestamp -
                lastNodeRewardClaimedTime[msg.sender];
            require(timePassed >= reward_interval, "Claim in 24 hours");
            rewards = _calculateNodeRewards(msg.sender);
            require(rewards > 0, "No node rewards to claim");
            require(
                rewards <= rewardToken.balanceOf(address(this)),
                "Insufficient Contract Balance"
            );

            lastNodeClaimedDay[msg.sender] = today;
            lastNodeRewardClaimedTime[msg.sender] = block.timestamp;
            nodesOwnedPerDay[msg.sender][today] = users[msg.sender].nodesOwned;
        }

        totalNodeRewardClaimed += rewards;
        users[msg.sender].totalNodeRewardReceived += rewards;
        rewardToken.safeTransfer(msg.sender, rewards);

        emit NodeRewardClaimed(msg.sender, rewards);
    }

    function claimMyReferralRewards() external nonReentrant {
        require(block.timestamp >= programStartTime, "Not started yet");

        address user = msg.sender;
        uint256 today = (block.timestamp - programStartTime) / reward_interval;

        uint256 rewards;

        if (!migrationRewardWindowClosed) {
            // ✅ Migration window still open (72h grace)
            require(
                block.timestamp <= migrationTime + migrationDuration,
                "Claim window expired"
            );

            rewards = _calculateReferralRewards(user);
            require(rewards > 0, "No rewards to claim");

            lastReferralClaimedDay[user] = today;
            lastReferralRewardClaimedTime[user] = block.timestamp;
        } else {
            // ✅ After 72h claim window

            if (lastReferralClaimedDay[user] == 0) {
                // ❗ User missed the window → start fresh from cutoff
                lastReferralClaimedDay[user] = migrationCutoffDay;

                // ⏪ Store node levels on cutoff day for fallback tracking
                for (uint256 level = 1; level <= 3; level++) {
                    dailyReferralNodesEachLevel[user][migrationCutoffDay][
                        level
                    ] = referrals[user].nodesEachLevel[level];
                }
            }

            // ✅ Enforce reward interval (e.g., once per 24h)
            uint256 daysPassed = today - lastReferralClaimedDay[user];
            require(
                daysPassed * reward_interval >= reward_interval,
                "Claim in 24 hours"
            );

            rewards = _calculateReferralRewards(user);
            require(rewards > 0, "No rewards to claim");

            lastReferralClaimedDay[user] = today;
            lastReferralRewardClaimedTime[user] = block.timestamp;
        }

        // ✅ Store today's referral snapshot for continuity
        for (uint256 level = 1; level <= 3; level++) {
            dailyReferralNodesEachLevel[user][today][level] = referrals[user]
                .nodesEachLevel[level];
        }

        // ✅ Transfer rewards
        require(
            rewards <= rewardToken.balanceOf(address(this)),
            "Insufficient Contract Balance"
        );

        users[user].totalRefRewardReceived += rewards;
        totalReferralRewardClaimed += rewards;

        rewardToken.safeTransfer(user, rewards);
        _updateRank(user);
        emit ReferralRewardClaimed(user, rewards);
    }

    function claimCoFounderRewards(uint256 _poolId) external nonReentrant {
        require(isClaimDay(), "Only claim 5 of every month");
        require(isCoFounder[msg.sender], "Not a coFounder");
        require(_poolId == coFounderPoolID, "Invalid Pool");

        require(
            block.timestamp >= programStartTime + time_interva_coFounder,
            "Not started yet"
        );

        uint256 claimableReward = _calculateCoFounderRewards(
            msg.sender,
            _poolId
        );
        require(claimableReward > 0, "No reward to claim");

        lastCoFounderClaimedTime[msg.sender] = block.timestamp;
        require(
            claimableReward <= rewardToken.balanceOf(address(this)),
            "Insufficient Balance"
        );

        rewardToken.safeTransfer(msg.sender, claimableReward);
    }

    function claimRankReward() external nonReentrant {
        require(block.timestamp >= programStartTime, "Not started yet");
        require(isClaimDay(), "Only claim 5 of every month");

        uint256 reward = _calculateRankRewards(msg.sender);

        require(reward > 0, "No reward to claim");
        require(
            reward <= rewardToken.balanceOf(address(this)),
            "Insufficient Balance"
        );

        lastRankClaimedTime[msg.sender] = block.timestamp;

        rewardToken.safeTransfer(msg.sender, reward);
    }

    function _distributeCashReferralRewards(
        address user,
        uint256 totalReferralAmount,
        uint256 nodeCount
    ) private {
        ReferralInfo storage refInfo = referrals[user];
        address currentReferrer = refInfo.referrer;

        for (
            uint256 level = 1;
            level <= 3 && currentReferrer != address(0);
            level++
        ) {
            ReferralInfo storage cuurentRefInfo = referrals[currentReferrer];
            //snapshot part
            uint256 day = (block.timestamp - programStartTime) /
                reward_interval;
            dailyReferralNodesEachLevel[currentReferrer][day][
                level
            ] += nodeCount;
            cuurentRefInfo.nodesEachLevel[level] += nodeCount;
            uint256 amount;
            if (level == 1)
                amount =
                    (totalReferralAmount * (firstLevelCashReward)) /
                    BASE_DIVIDER; // 7%
            else if (level == 2)
                amount =
                    (totalReferralAmount * (secondLevelCashReward)) /
                    BASE_DIVIDER; // 3%
            else
                amount =
                    (totalReferralAmount * (thirdLevelCashReward)) /
                    BASE_DIVIDER; // 1%

            ReferralInfo storage referrerInfo = referrals[currentReferrer];

            users[currentReferrer].totalCashReceived += amount;
            cashRewardToken.safeTransfer(currentReferrer, amount);

            emit ReferralRewardAdded(currentReferrer, user, level, amount);

            currentReferrer = referrerInfo.referrer;
        }
    }

    function _calculateRankRewards(
        address _user
    ) internal view returns (uint256) {
        if (isBlocked[_user]) return 0;

        Rank currentRank = checkMyRank(_user);
        uint256 totalReward;

        if (currentRank >= Rank.AlphaAmbassador) {
            for (
                uint256 i = uint256(Rank.AlphaAmbassador);
                i <= uint256(currentRank);
                i++
            ) {
                Rank rank = Rank(i);
                uint256 rewardRate = getPoolRewardRate(uint256(rank)); // tokens per year
                uint256 participantsCount = pools[uint256(rank)]
                    .participants
                    .length;
                uint256 rewardStart = pools[uint256(rank)].rewardStartTime;

                if (participantsCount == 0 || rewardStart == 0) continue;

                uint256 timePassed = lastRankClaimedTime[_user] == 0 ||
                    lastRankClaimedTime[_user] < rewardStart
                    ? block.timestamp - rewardStart
                    : block.timestamp - lastRankClaimedTime[_user];

                uint256 claimableReward = (rewardRate *
                    timePassed *
                    BASE_DECIMALS) / (365 days * participantsCount);

                totalReward += claimableReward;
            }
        }

        return totalReward / BASE_DECIMALS;
    }

    function _calculateCoFounderRewards(
        address user,
        uint256 _poolId
    ) internal view returns (uint256) {
        if (isBlocked[user]) return 0;
        uint256 rewardRate = getPoolRewardRate(_poolId);
        uint256 claimableReward = ((rewardRate * BASE_DECIMALS) /
            NodeSale(nodeSaleContract).maxCoFounders()) / 365 days;

        uint256 timesPassed;

        if (
            block.timestamp < coFounderEntryTime[user] + time_interva_coFounder
        ) {
            timesPassed = 0;
        } else {
            timesPassed = lastCoFounderClaimedTime[user] == 0
                ? block.timestamp -
                    (coFounderEntryTime[user] + time_interva_coFounder)
                : block.timestamp - lastCoFounderClaimedTime[user];
        }

        return (claimableReward * timesPassed) / BASE_DECIMALS;
    }

    function _calculateNodeRewards(
        address user
    ) private view returns (uint256) {
        UserInfo storage userInfo = users[user];
        if (userInfo.nodesOwned == 0 || programStartTime == 0) return 0;
        if (isBlocked[user]) return 0;

        uint256 today = (block.timestamp - programStartTime) / reward_interval;
        uint256 fromDay;
        uint256 totalReward = 0;

        if (
            userInfo.entryTime < programStartTime &&
            lastNodeClaimedDay[user] == 0 &&
            block.timestamp > migrationTime &&
            !migrationRewardWindowClosed
        ) {
            uint256 rewardPerDay = getCurrentRewardRate() / totalNodesSold;
            uint256 daysPassed = (block.timestamp - programStartTime) /
                reward_interval;
            totalReward += daysPassed * rewardPerDay * userInfo.nodesOwned;
        } else if (
            userInfo.entryTime > programStartTime &&
            userInfo.entryTime < migrationTime &&
            block.timestamp > migrationTime &&
            !migrationRewardWindowClosed &&
            lastNodeClaimedDay[user] == 0
        ) {
            uint256 rewardPerDay = getCurrentRewardRate() / totalNodesSold;
            uint256 daysPassed = (block.timestamp - userInfo.entryTime) /
                reward_interval;
            totalReward += daysPassed * rewardPerDay * userInfo.nodesOwned;
        } else {
            fromDay = lastNodeClaimedDay[user];
            uint256 toDay = today - 1;

            uint256 lastKnownNodes = 0;

            for (uint256 d = fromDay; d <= toDay; d++) {
                uint256 nodesToday = nodesOwnedPerDay[user][d];

                if (nodesToday == 0 && d > 0) {
                    nodesToday = lastKnownNodes;
                } else {
                    lastKnownNodes = nodesToday;
                }

                uint256 perNode = dailySnapshots[d].rewardPerNode;
                totalReward += nodesToday * perNode;
            }
        }

        return totalReward;
    }

    function _calculateReferralRewards(
        address user
    ) private view returns (uint256) {
        if (programStartTime == 0) return 0;
        if (isBlocked[user]) return 0;

        ReferralInfo storage refInfo = referrals[user];
        if (
            refInfo.nodesEachLevel[0] == 0 &&
            refInfo.nodesEachLevel[1] == 0 &&
            refInfo.nodesEachLevel[2] == 0
        ) return 0;

        uint256 today = (block.timestamp - programStartTime) / reward_interval;
        uint256 fromDay = lastReferralClaimedDay[user];
        if (fromDay >= today) return 0;

        uint256 toDay = today - 1;
        uint256 totalRewards = 0;

        uint256[4] memory lastKnownNodes;
        uint256[4] memory levelRewardPercents = [
            uint256(0), // dummy index
            firstLevelReward,
            secondLevelReward,
            thirdLevelReward
        ];

        if (!migrationRewardWindowClosed && lastReferralClaimedDay[user] == 0) {
            // ✅ Fallback to legacy logic
            uint256 rewardRate = getCurrentRewardRate() / totalNodesSold;

            for (uint256 level = 1; level <= 3; level++) {
                uint256 nodeCount = refInfo.nodesEachLevel[level];
                uint256 nodeRewards = nodeCount * rewardRate * today;
                uint256 refReward = (nodeRewards * levelRewardPercents[level]) /
                    BASE_DIVIDER;
                totalRewards += refReward;
            }
        } else {
            // ✅ Post-migration logic using per-day tracking
            for (uint256 d = fromDay; d <= toDay; d++) {
                uint256 perNodeReward = dailySnapshots[d].rewardPerNode;

                for (uint256 level = 1; level <= 3; level++) {
                    uint256 nodeCount = dailyReferralNodesEachLevel[user][d][
                        level
                    ];

                    // Fallback if node count not recorded
                    if (nodeCount == 0 && d > 0) {
                        if (lastKnownNodes[level] == 0) {
                            lastKnownNodes[level] = referrals[user]
                                .nodesEachLevel[level];
                        }
                        nodeCount = lastKnownNodes[level];
                    } else {
                        lastKnownNodes[level] = nodeCount;
                    }

                    uint256 nodeRewards = nodeCount * perNodeReward;
                    uint256 refReward = (nodeRewards *
                        levelRewardPercents[level]) / BASE_DIVIDER;
                    totalRewards += refReward;
                }
            }
        }

        return totalRewards;
    }

    function _setReferrer(address user, address referrer) private {
        if (
            referrer != address(0) &&
            referrer != user &&
            referrals[user].referrer == address(0)
        ) {
            referrals[user].referrer = referrer;
            referrals[referrer].directTeam.push(user);
        }
    }

    function _updateRank(address _user) internal {
        UserInfo storage userinfo = users[_user];

        Rank oldRank = userinfo.currentRank;
        Rank newRank = checkMyRank(_user);

        if (newRank <= oldRank) return;

        uint256 start = uint256(oldRank) + 1;
        uint256 minPool = uint256(Rank.AlphaAmbassador);
        if (start < minPool) start = minPool;

        for (uint256 rr = start; rr <= uint256(newRank); rr++) {
            if (!isPoolParticipant[rr][_user]) {
                isPoolParticipant[rr][_user] = true;
                pools[rr].participants.push(_user);
            }

            if (
                pools[rr].participants.length >=
                usersRequiredForRankReward[rr] &&
                pools[rr].rewardStartTime == 0
            ) {
                pools[rr].rewardStartTime = block.timestamp;
            }
        }

        userinfo.currentRank = newRank;
    }

    function recordDailyReward() public onlyRole(SNAPSHOT_ROLE) {
        uint256 day = (block.timestamp - programStartTime) / reward_interval;

        DailySnapshot storage snap = dailySnapshots[day];
        snap.totalReward = getCurrentRewardRate();

        snap.totalNodes = snap.totalNodes > 0
            ? snap.totalNodes
            : totalNodesSold;

        if (snap.totalNodes > 0 && snap.totalReward > 0) {
            snap.rewardPerNode = snap.totalReward / snap.totalNodes;
        }
    }

    // View functions

    function isClaimDay() public view returns (bool) {
        (, , uint256 day) = BokkyPooBahsDateTimeLibrary.timestampToDate(
            block.timestamp
        );
        return day == claimDay;
    }

    function getCurrentMonth() public view returns (uint256) {
        (, uint256 month, ) = BokkyPooBahsDateTimeLibrary.timestampToDate(
            block.timestamp
        );
        return month;
    }

    function checkMyRank(address _user) public view returns (Rank) {
        UserInfo storage userinfo = users[_user];
        ReferralInfo storage refinfo = referrals[_user];
        Rank currentRank = userinfo.currentRank;

        if (currentRank == Rank.Global) return currentRank;

        for (
            uint256 r = uint256(currentRank) + 1;
            r <= uint256(Rank.Global);
            r++
        ) {
            Rank nextRank = Rank(r);

            if (
                refinfo.teamNodes <
                rankRequirements[nextRank].nodeRequirement ||
                Staking(stakingContract).getUserTotalStakeAmount(_user) <
                rankRequirements[nextRank].stakingAmount
            ) {
                break;
            }

            uint256 requiredFromOne = (rankRequirements[nextRank]
                .nodeRequirement *
                rankRequirements[nextRank].referralPercentage) / BASE_DIVIDER;

            uint256 requiredFromOthers = rankRequirements[nextRank]
                .nodeRequirement - requiredFromOne;

            uint256 maxLeg = maxDirectTeamNodes[_user];
            uint256 total = totalDirectTeamNodes[_user];

            if (
                maxLeg >= requiredFromOne &&
                (total - maxLeg) >= requiredFromOthers
            ) {
                currentRank = nextRank;
            } else {
                break;
            }
        }

        return currentRank;
    }

    function getDirectTeamWithNodeCounts(
        address _user
    ) external view returns (TeamMemberWithNodes[] memory) {
        ReferralInfo storage userInfo = referrals[_user];
        uint256 teamSize = userInfo.directTeam.length;

        TeamMemberWithNodes[] memory teamData = new TeamMemberWithNodes[](
            teamSize
        );

        for (uint256 i = 0; i < teamSize; i++) {
            address member = userInfo.directTeam[i];
            teamData[i] = TeamMemberWithNodes({
                memberId: NodeSale(nodeSaleContract).addressToID(member),
                nodeCount: referrals[member].teamNodes
            });
        }

        return teamData;
    }

    function getCurrentRewardRate() public view returns (uint256) {
        if (
            totalNodesSold == 0 ||
            programStartTime == 0 ||
            block.timestamp < programStartTime
        ) {
            return 0;
        }

        // Calculate normalized time passed once
        uint256 timePassed = ((block.timestamp - programStartTime) *
            BASE_DECIMALS) / time_interval;

        uint256 dailyReward;
        if (timePassed <= 2 * BASE_DECIMALS) {
            dailyReward = FIRST_AND_2ND_YEAR_DAILY_REWARD;
        } else if (timePassed <= 4 * BASE_DECIMALS) {
            dailyReward = THIRD_AND_4TH_YEAR_DAILY_REWARD;
        } else if (timePassed <= 5 * BASE_DECIMALS) {
            dailyReward = FIFTH_YEAR_DAILY_REWARD;
        } else if (timePassed <= 6 * BASE_DECIMALS) {
            dailyReward = SIXTH_YEAR_DAILY_REWARD;
        } else {
            dailyReward = SEVENTH_YEAR_DAILY_REWARD;
        }

        return dailyReward;
    }

    function getPoolRewardRate(uint256 _poolId) public view returns (uint256) {
        if (block.timestamp < programStartTime) {
            return 0;
        }
        RewardPool storage pool = pools[_poolId];
        uint256 yearPassed = ((block.timestamp - programStartTime) *
            BASE_DECIMALS) / time_interval;

        if (yearPassed > 7 * BASE_DECIMALS) {
            return 0;
        }

        if (yearPassed > 6 * BASE_DECIMALS) {
            return pool.seventhYearAmount;
        } else if (yearPassed > 5 * BASE_DECIMALS) {
            return pool.sixthYearAmount;
        } else if (yearPassed > 4 * BASE_DECIMALS) {
            return pool.fifthYearAmount;
        } else if (yearPassed > 3 * BASE_DECIMALS) {
            return pool.fourthYearAmount;
        } else if (yearPassed > 2 * BASE_DECIMALS) {
            return pool.thirdYearAmount;
        } else if (yearPassed > 1 * BASE_DECIMALS) {
            return pool.secondYearAmount;
        } else {
            return pool.firstYearAmount;
        }
    }

    function getMyReferer(address user) public view returns (address) {
        return referrals[user].referrer;
    }

    function teamNodeCount(address _user) external view returns (uint256) {
        return referrals[_user].teamNodes;
    }

    function myDirectTeam(
        address _user
    ) external view returns (address[] memory) {
        return referrals[_user].directTeam;
    }

    function getMyDirectRefCount(address user) public view returns (uint256) {
        return referrals[user].directTeam.length;
    }

    function getPendingNodeRewards(
        address user
    ) external view returns (uint256) {
        return _calculateNodeRewards(user);
    }

    function getPendingReferralRewards(
        address referrer
    ) external view returns (uint256) {
        return _calculateReferralRewards(referrer);
    }

    function getPendingRankRewards(
        address user
    ) external view returns (uint256) {
        return _calculateRankRewards(user);
    }

    function getPendingCoFounderRewards(
        address user,
        uint256 _poolId
    ) external view returns (uint256) {
        return _calculateCoFounderRewards(user, _poolId);
    }

    function getEligibleRefRewardPercentage(
        address referrar
    ) public view returns (uint256) {
        address currentReferrer = referrar;

        uint256 totalRewardPercentage = 0;

        for (
            uint256 level = 1;
            level <= 3 && currentReferrer != address(0);
            level++
        ) {
            if (level == 1) {
                totalRewardPercentage += firstLevelCashReward;
            } else if (level == 2) {
                totalRewardPercentage += secondLevelCashReward;
            } else {
                totalRewardPercentage += thirdLevelCashReward;
            }

            ReferralInfo storage referrerInfo = referrals[currentReferrer];

            currentReferrer = referrerInfo.referrer;
        }

        return totalRewardPercentage;
    }

    function getDays() public view returns (uint256) {
        return (block.timestamp - programStartTime) / reward_interval;
    }

    function poolUsers(uint256 _poolId) public view returns (uint256) {
        return pools[_poolId].participants.length;
    }

    //Admin functions
    function addPool(
        uint256 _firstYearAmount,
        uint256 _secondYearAmount,
        uint256 _thirdYearAmount,
        uint256 _fourthYearAmount,
        uint256 _fifthYearAmount,
        uint256 _sixthYearAmount,
        uint256 _seventhYearAmount
    ) external onlyOwner {
        RewardPool storage pool = pools[totalPools];
        pool.poolId = totalPools;
        pool.firstYearAmount = _firstYearAmount;
        pool.secondYearAmount = _secondYearAmount;
        pool.thirdYearAmount = _thirdYearAmount;
        pool.fourthYearAmount = _fourthYearAmount;
        pool.fifthYearAmount = _fifthYearAmount;
        pool.sixthYearAmount = _sixthYearAmount;
        pool.seventhYearAmount = _seventhYearAmount;

        totalPools++;
    }

    function setCoFounderPool(uint256 _poolId) external onlyOwner {
        require(_poolId > 0, "Invalid poolId");
        require(pools[_poolId].poolId != 0, "Invalid Pool");
        coFounderPoolID = _poolId;
    }

    function updatePool(
        uint256 _poolId,
        uint256 _firstYearAmount,
        uint256 _secondYearAmount,
        uint256 _thirdYearAmount,
        uint256 _fourthYearAmount,
        uint256 _fifthYearAmount,
        uint256 _sixthYearAmount,
        uint256 _seventhYearAmount
    ) external onlyOwner {
        RewardPool storage pool = pools[_poolId];
        pool.firstYearAmount = _firstYearAmount;
        pool.secondYearAmount = _secondYearAmount;
        pool.thirdYearAmount = _thirdYearAmount;
        pool.fourthYearAmount = _fourthYearAmount;
        pool.fifthYearAmount = _fifthYearAmount;
        pool.sixthYearAmount = _sixthYearAmount;
        pool.seventhYearAmount = _seventhYearAmount;
    }

    function updateRankRequirements(
        Rank rank,
        uint256 nodeReq,
        uint256 referralPct,
        uint256 stakingAmount
    ) external onlyOwner {
        rankRequirements[rank] = RankRequirements(
            nodeReq,
            referralPct,
            stakingAmount
        );
    }

    function updateClaimDay(uint256 _newDay) external onlyOwner {
        require(_newDay > 0, "Invalid Date");
        claimDay = _newDay;
    }

    function updateTimeInterval(uint256 _newTime) external onlyOwner {
        require(_newTime > 0, "Invalid Time");
        time_interval = _newTime;
    }

    function updateContracts(
        address _cash,
        address _reward,
        address _node,
        address _staking
    ) external onlyOwner {
        require(
            _cash != address(0) &&
                _reward != address(0) &&
                _node != address(0) &&
                _staking != address(0),
            "can't be 0 address"
        );

        cashRewardToken = IERC20(_cash);
        rewardToken = IERC20(_reward);
        nodeSaleContract = _node;
        stakingContract = _staking;
    }

    function updateCashLevelRate(
        uint256 _level1Rate,
        uint256 _level2Rate,
        uint256 _level3Rate
    ) external onlyOwner {
        require(
            _level1Rate > 0 && _level2Rate > 0 && _level3Rate > 0,
            "Can't be 0 Value"
        );
        firstLevelCashReward = _level1Rate;
        secondLevelCashReward = _level2Rate;
        thirdLevelCashReward = _level3Rate;
    }

    function updateLevelRate(
        uint256 _level1Rate,
        uint256 _level2Rate,
        uint256 _level3Rate
    ) external onlyOwner {
        require(
            _level1Rate > 0 && _level2Rate > 0 && _level3Rate > 0,
            "Can't be 0 Value"
        );
        firstLevelReward = _level1Rate;
        secondLevelReward = _level2Rate;
        thirdLevelReward = _level3Rate;
    }

    function updateUsersRequiredForRankRewards(
        uint256[6] calldata newRewards
    ) external onlyOwner {
        usersRequiredForRankReward = newRewards;
    }

    function updateCoFounderInterval(uint256 _newTime) external onlyOwner {
        time_interva_coFounder = _newTime;
    }

    function updateNodeRequiredForLaunch(
        uint256 _newAmount
    ) external onlyOwner {
        require(_newAmount > 0, "can't be 0");
        nodeRequiredToLaunch = _newAmount;
    }

    function blockWallet(address _user) external onlyOwner {
        require(_user != address(0), "Zero Address");
        require(!isBlocked[_user], "Already Blocked");
        isBlocked[_user] = true;
    }

    function unBlockWallet(address _user) external onlyOwner {
        require(_user != address(0), "Zero Address");
        require(isBlocked[_user], "Not Blocked");
        uint256 day = (block.timestamp - programStartTime) / reward_interval;
        lastNodeClaimedDay[_user] = day;
        lastReferralClaimedDay[_user] = day;
        lastNodeRewardClaimedTime[_user] = block.timestamp;
        lastReferralRewardClaimedTime[_user] = block.timestamp;
        lastRankClaimedTime[_user] = block.timestamp;
        lastCoFounderClaimedTime[_user] = block.timestamp;
        isBlocked[_user] = false;
    }

    function withdrawToken(address _token, uint256 _amount) external onlyOwner {
        require(_token != address(0), "Invalid Token");
        require(_amount > 0, "Invalid Amount");
        require(
            _amount <= IERC20(_token).balanceOf(address(this)),
            "Insufficient Contract Balance"
        );
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    function updateYearlyReward(
        uint256 _firstAnd2nd,
        uint256 _thirdAnd4th,
        uint256 _fifth,
        uint256 _sixth,
        uint256 _seventh
    ) external onlyOwner {
        require(
            _firstAnd2nd > 0 &&
                _thirdAnd4th > 0 &&
                _fifth > 0 &&
                _sixth > 0 &&
                _seventh > 0,
            "Invalid Amount"
        );

        FIRST_AND_2ND_YEAR_DAILY_REWARD = _firstAnd2nd;
        THIRD_AND_4TH_YEAR_DAILY_REWARD = _thirdAnd4th;
        FIFTH_YEAR_DAILY_REWARD = _fifth;
        SIXTH_YEAR_DAILY_REWARD = _sixth;
        SEVENTH_YEAR_DAILY_REWARD = _seventh;
    }

    // migration
    function finalizeMigration() external onlyOwner {
        require(!migrationRewardWindowClosed, "Migration already finalized");
        require(
            block.timestamp > migrationTime + migrationDuration,
            "Too early"
        );
        migrationRewardWindowClosed = true;
        migrationCutoffDay =
            (migrationTime + migrationDuration - programStartTime) /
            reward_interval;
    }

    function updateMigrationDuration(uint256 _newDuration) external onlyOwner {
        require(!migrationRewardWindowClosed, "Migration already finalized");
        require(_newDuration > 0, "Invalid Duration");
        migrationDuration = _newDuration;
    }

    function batchMigrateFullUserData(
        MigrationInput[] calldata data
    ) external onlyOwner {
        for (uint256 i = 0; i < data.length; i++) {
            address user = data[i].user;
            if (hasMigrated[user]) continue;

            referrals[user].referrer = data[i].referrer;
            referrals[user].directTeam = data[i].directteam;
            referrals[user].teamNodes += data[i].teamNode;

            referrals[user].nodesEachLevel[1] = data[i].levels[0];
            referrals[user].nodesEachLevel[2] = data[i].levels[1];
            referrals[user].nodesEachLevel[3] = data[i].levels[2];

            users[user].nodesOwned = data[i].nodesOwned;
            users[user].entryTime = data[i].entryTime;
            users[user].totalCashReceived = data[i].totalCashReceived;
            users[user].currentRank = data[i].currentRank;

            hasMigrated[user] = true;
        }
    }
}
