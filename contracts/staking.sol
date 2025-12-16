// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./referral.sol";

contract MavroStaking is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    uint256 public rewardPoolBalance;

    MavroNewReferralsSystem public referralSystem;
    struct Stake {
        uint256 amount;
        uint256 startTime;
        uint256 endTime;
        uint8 plan;
        uint256 lastClaimTime;
        uint256 totalClaimed;
        bool isUnstaked;
    }

    struct Plan {
        uint256 duration; // in seconds
        uint256 apy; // percentage (e.g., 25 for 25%)
        uint8[3] refCommissions; // level1, level2, level3 percentages
        bool deprecated;
    }

    IERC20 public stakingToken;

    // Staking limits
    uint256 public minStakeAmount = 5000 * (10**18); // Default minimum 5000 tokens (assuming 18 decimals)
    uint256 public maxStakeAmount = type(uint256).max; // Unlimited by default

    uint256 public totalTokenStaked;

    mapping(address => Stake[]) public stakes;
    mapping(address => address) public referrers;
    mapping(address => uint256) public referralRewardsEarned;
    mapping(address => uint256) public totalStaked;
    mapping(address => uint256) public totalEarned;
    mapping(address => mapping(uint256 => Stake[])) refStakesPerLevel;
    mapping(address => uint256) public lastRewardClaimedTime;
    mapping(address => uint256) public lastGenRewardClaimedTime;
    mapping(address => uint256) public teamStaked;

    Plan[] public plans;
    uint256[] public genRewards = [3, 1, 1];

    event Staked(address indexed user, uint256 amount, uint8 plan);
    event Unstaked(address indexed user, uint256 amount);
    event ReferralCommission(
        address indexed referrer,
        address indexed referee,
        uint256 amount,
        uint8 level
    );
    event TokensRecovered(address token, uint256 amount);
    event StakingLimitsUpdated(uint256 minAmount, uint256 maxAmount);

    constructor(IERC20 _stakingToken, address _referralSystem)
        Ownable(msg.sender)
    {
        require(address(_stakingToken) != address(0), "Invalid token");
        require(_referralSystem != address(0), "Invalid referral system");
        require(isContract(_referralSystem), "Referral must be contract");

        stakingToken = _stakingToken;
        referralSystem = MavroNewReferralsSystem(_referralSystem);

        plans.push(Plan(180 days, 25, [3, 1, 1], false));

        plans.push(Plan(365 days, 60, [7, 3, 1], false));

        plans.push(Plan(1095 days, 200, [10, 3, 1], false));

        plans.push(Plan(1825 days, 400, [15, 3, 1], false));
    }

    function stake(uint256 _amount, uint8 _plan)
        external
        nonReentrant
        whenNotPaused
    {
        require(_plan < plans.length, "Invalid plan");
        require(!plans[_plan].deprecated, "Plan deprecated");
        require(_amount >= minStakeAmount, "Amount below minimum stake limit");
        require(
            _amount <= maxStakeAmount,
            "Amount exceeds maximum stake limit"
        );

        Plan memory plan = plans[_plan];

        // Create new stake
        Stake memory _stake = Stake({
            amount: _amount,
            startTime: block.timestamp,
            endTime: block.timestamp + plan.duration,
            plan: _plan,
            lastClaimTime: block.timestamp,
            totalClaimed: 0,
            isUnstaked: false
        });
        stakes[msg.sender].push(_stake);

        totalStaked[msg.sender] += _amount;
        totalTokenStaked += _amount;

        stakingToken.safeTransferFrom(msg.sender, address(this), _amount);

        distributeReferralCommissions(_amount, _plan, _stake);

        emit Staked(msg.sender, _amount, _plan);
    }

    function distributeReferralCommissions(
        uint256 _amount,
        uint8 _plan,
        Stake memory _stake
    ) internal {
        Plan memory plan = plans[_plan];

        address currentRef = referralSystem.getMyReferer(msg.sender);
        for (uint8 i = 0; i < 3; i++) {
            if (currentRef == address(0)) break;

            uint256 commission = (_amount * plan.refCommissions[i]) / 100;

            referralRewardsEarned[currentRef] += commission;

            teamStaked[currentRef] += _amount;

            refStakesPerLevel[currentRef][i].push(_stake);

            require(
                rewardPoolBalance >= commission,
                "Insufficient reward pool"
            );
            rewardPoolBalance -= commission;

            require(
                stakingToken.transfer(currentRef, commission),
                "Ref Commission transfer failed"
            );

            emit ReferralCommission(currentRef, msg.sender, commission, i + 1);

            // Move to the next level referrer
            currentRef = referralSystem.getMyReferer(currentRef);
        }
    }

    function unstake(uint256 _stakeIndex) external nonReentrant {
        require(_stakeIndex < stakes[msg.sender].length, "Invalid stake index");
        Stake storage userStake = stakes[msg.sender][_stakeIndex];
        require(
            block.timestamp >= userStake.endTime,
            "Staking period not ended"
        );

        uint256 pending = _calculateClaimableReward(msg.sender, _stakeIndex);

        uint256 totalAmount = userStake.amount + pending;
        // totalEarned[msg.sender] += userStake.maxReward;

        totalStaked[msg.sender] -= userStake.amount;
        totalTokenStaked -= userStake.amount;
        userStake.isUnstaked = true;

        require(
            pending <= stakingToken.balanceOf(address(this)),
            "Insufficient Balance"
        );
        stakingToken.safeTransfer(msg.sender, totalAmount);

        emit Unstaked(msg.sender, userStake.amount);
    }

    function claimStakingReward() external nonReentrant {
        Stake[] storage Stakes = stakes[msg.sender];

        uint256 totalAmount;
        for (uint256 i = 0; i < Stakes.length; i++) {
            if (Stakes[i].isUnstaked) continue;
            uint256 reward = _calculateClaimableReward(msg.sender, i);
            totalAmount += reward;
            Stakes[i].lastClaimTime = block.timestamp;
            Stakes[i].totalClaimed += reward;
        }

        require(totalAmount > 0, "No reward to claim");
        require(
            totalAmount <= stakingToken.balanceOf(address(this)),
            "Insufficient Balance"
        );
        stakingToken.safeTransfer(msg.sender, totalAmount);
    }

    function claimGenReward() external nonReentrant {
        uint256 reward = claimableGenReward(msg.sender);
        require(reward > 0, "No reward to claim");
        lastGenRewardClaimedTime[msg.sender] = block.timestamp;
        require(
            reward <= stakingToken.balanceOf(address(this)),
            "Insufficient Balance"
        );
        stakingToken.safeTransfer(msg.sender, reward);
    }

    //view functions

    function getUserTotalStakeAmount(address _user)
        public
        view
        returns (uint256)
    {
        Stake[] storage _stakes = stakes[_user];
        uint256 totalAmount;

        for (uint256 i = 0; i < _stakes.length; i++) {
            if (!_stakes[i].isUnstaked) {
                totalAmount += _stakes[i].amount;
            }
        }
        return totalAmount;
    }

    function claimableGenReward(address _user)
        public
        view
        returns (uint256 totalReward)
    {
        uint256 currentTime = block.timestamp;
        uint256 lastClaimed = lastGenRewardClaimedTime[_user];

        for (uint256 level = 0; level < 3; level++) {
            Stake[] storage levelStakes = refStakesPerLevel[_user][level];
            uint256 levelRewardRate = genRewards[level];
            uint256 levelStakesCount = levelStakes.length;

            if (levelStakesCount == 0) continue;

            // Use unchecked for gas savings (we know levelStakesCount > 0)
            unchecked {
                for (uint256 j = 0; j < levelStakesCount; j++) {
                    Stake storage userStake = levelStakes[j];
                    Plan memory plan = plans[userStake.plan];

                    uint256 startTime = lastClaimed > userStake.startTime
                        ? lastClaimed
                        : userStake.startTime;

                    uint256 endTime = currentTime > userStake.endTime
                        ? userStake.endTime
                        : currentTime;

                    if (endTime > startTime) {
                        uint256 timePassed = endTime - startTime;
                        uint256 stakingReward = (userStake.amount *
                            plan.apy *
                            timePassed) / (100 * plan.duration);
                        totalReward += (stakingReward * levelRewardRate) / 100;
                    }
                }
            }
        }
    }

    function claimableStakingReward(address _user)
        public
        view
        returns (uint256)
    {
        uint256 totalAmount;
        for (uint256 i = 0; i < stakes[_user].length; i++) {
            uint256 reward = _calculateClaimableReward(_user, i);
            totalAmount += reward;
        }

        return totalAmount;
    }

    function getUserStakes(address _user)
        external
        view
        returns (Stake[] memory)
    {
        return stakes[_user];
    }

    function getPlans() external view returns (Plan[] memory) {
        return plans;
    }

    function isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }

    function _calculateClaimableReward(address _user, uint256 _stakeIndex)
        internal
        view
        returns (uint256)
    {
        Stake memory userStake = stakes[_user][_stakeIndex];

        if (userStake.isUnstaked) return 0;

        Plan memory plan = plans[userStake.plan];
        uint256 endTime = block.timestamp >= userStake.endTime
            ? userStake.endTime
            : block.timestamp;

        uint256 timePassed = endTime - userStake.lastClaimTime;
        if (timePassed == 0) return 0;

        uint256 rewardPerSecond = (userStake.amount * plan.apy) /
            (100 * plan.duration);
        uint256 earnedReward = rewardPerSecond * timePassed;

        return earnedReward;
    }

    // ========= Owner functions ========== //
    // =================================== //

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setStakingLimits(uint256 _minAmount, uint256 _maxAmount)
        external
        onlyOwner
    {
        require(
            _minAmount <= _maxAmount,
            "Minimum cannot be greater than maximum"
        );
        minStakeAmount = _minAmount;
        maxStakeAmount = _maxAmount;
        emit StakingLimitsUpdated(_minAmount, _maxAmount);
    }

    function fundRewardPool(uint256 amount) external onlyOwner {
        require(amount > 0, "Invalid Amount");
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        rewardPoolBalance += amount;
    }

    function updatePlan(
        uint256 planId,
        uint256 duration,
        uint256 apy,
        uint8[3] calldata refCommissions,
        bool _isDeprecated
    ) external onlyOwner {
        require(apy > 0 && apy <= 1000, "Invalid APY"); // Max 1000% APY
        require(duration > 0, "Duration too short");
        require(
            refCommissions[0] + refCommissions[1] + refCommissions[2] <= 100,
            "Total commissions exceed 100%"
        );

        if (planId < plans.length) {
            // Update existing plan
            Plan storage plan = plans[planId];
            plan.duration = duration;
            plan.apy = apy;
            plan.refCommissions = refCommissions;
            plan.deprecated = _isDeprecated;
        } else {
            // Add new plan
            plans.push(Plan(duration, apy, refCommissions, _isDeprecated));
        }
    }

    function updateGenRewards(uint256[3] calldata newRewards)
        external
        onlyOwner
    {
        require(
            newRewards[0] <= 100 &&
                newRewards[1] <= 100 &&
                newRewards[2] <= 100,
            "Reward rate too high"
        );

        genRewards = newRewards;
    }

    function deprecatePlan(uint256 planId) external onlyOwner {
        require(planId < plans.length, "Invalid plan");
        plans[planId].deprecated = true;
    }

    function recoverTokens(address _token, uint256 _amount) external onlyOwner {
        require(
            _token != address(stakingToken),
            "Cannot withdraw staking token"
        );
        IERC20(_token).safeTransfer(owner(), _amount);
        emit TokensRecovered(_token, _amount);
    }

    function updateContracts(address _token, address _referal)
        external
        onlyOwner
    {
        require(
            _token != address(0) && _referal != address(0),
            "Invalid contract"
        );
        stakingToken = IERC20(_token);
        referralSystem = MavroNewReferralsSystem(_referal);
    }

    function setStakingToken(IERC20 _stakingToken) external onlyOwner {
        stakingToken = _stakingToken;
    }
}
