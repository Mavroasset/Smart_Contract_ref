// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal imports from OpenZeppelin (owner + reentrancy)
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
}

library SafeTransfer {
    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(token.transfer.selector, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "SafeTransfer: transfer failed"
        );
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(token.transferFrom.selector, from, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "SafeTransfer: transferFrom failed"
        );
    }
}

interface IREFERRAL {
    function getMyReferer(address user) external view returns (address);
}

contract MAVROPRESALE is Ownable, ReentrancyGuard, Pausable {
    using SafeTransfer for IERC20;

    // ---------- Errors ----------
    error ZeroAddress(string message);
    error StageNotStarted(string message);
    error StageEnded(string message);
    error BadStage(string message);
    error InsufficientStageTokens();
    error BelowMin(string message);
    error ExceedsMax(string message);
    error NothingToClaim(string message);
    error NotEnoughSaleTokens(string message);
    error ReferralTooHigh(string message);

    // ---------- Tokens ----------
    IERC20 public token;
    IERC20 public usdt;

    address public referralContract;

    address public fundReceiver;

    address public DEFAULT_REFERRER;

    uint256 public totalTokensSold;

    uint256 private constant BASIS_POINTS = 10_000;
    uint256 private constant PERCENT_DENOMINATOR = 100;

    // ---------- Vesting ----------
    uint256 public INITIAL_UNLOCK_PERCENT = 10; // 10%
    uint256 public LOCK_PERIOD = 90 days;
    uint256 public VESTING_DURATION = 365 days;

    // ---------- Referral ----------
    uint256 public level1RefPercent = 300;
    uint256 public level2RefPercent = 100;
    uint256 public level3RefPercent = 100;

    // ---------- Stages ----------
    struct Stage {
        uint256 tokensAvailable;
        uint256 tokensAlloted;
        uint256 tokensSold;
        uint64 startTime;
        uint32 duration;
        uint256 price;
        uint256 minAmount;
        uint256 maxAmount;
    }
    uint256 public constant TOTAL_STAGES = 3;
    uint256 public currentStage; // 0..2
    mapping(uint256 => Stage) public stages;

    // ---------- Purchases ----------
    struct Purchase {
        uint256 amount;
        uint256 claimed;
        uint64 timestamp;
    }
    mapping(address => Purchase[]) private _purchases;
    mapping(uint256 => mapping(address => uint256))
        public totalPurchasedInStage;
    mapping(address => uint256) public totalPurchased;
    mapping(address => uint256) public totalClaimed;
    bool public isMigrated;
    bool public isTotalMigrated;

    // ---------- Referrals accounting ----------
    mapping(address => uint256) public referralEarnings;

    // ---------- Events ----------
    event TokensPurchased(
        address indexed buyer,
        uint256 amount,
        uint256 tokenAmount,
        uint256 stage
    );
    event TokensClaimed(address indexed user, uint256 amount);
    event StageAdvanced(
        uint256 newStage,
        uint256 startTime,
        uint256 carriedOver
    );
    event StageTokensAdded(uint256 indexed stage, uint256 amount);
    event StageDurationUpdated(uint256 indexed stage, uint256 newDuration);
    event FundReceiverUpdated(address indexed newReceiver);
    event ReferralBpsUpdated(uint16 newBps);
    event ReferralPaid(
        address indexed referrer,
        address indexed buyer,
        uint256 usdtAmount
    );

    event InitialUnlockPercentUpdated(uint256 newPercent);
    event LockPeriodUpdated(uint256 newPeriod);
    event VestingDurationUpdated(uint256 newDuration);
    event StagePriceUpdated(uint256 stakeIndex, uint256 newPrice);
    event StageUpdated(
        uint256 stakeIndex,
        uint64 startTime,
        uint32 duration,
        uint256 price,
        uint256 minAmoun,
        uint256 maxAmount
    );

    event MigrationBatchReplaced(uint256 indexed batchId, uint256 usersCount);
    event MigrationPurchaseAppended(address indexed user, uint256 idx);

    // ---------- Constructor ----------
    /// @param _token sale token (18 decimals)
    /// @param _usdt  USDT token on BSC (18 decimals)
    /// @param _fundReceiver treasury receiving payments after referrals
    /// @param stage0StartTime if 0 => start now, else specified unix ts
    constructor(
        IERC20 _token,
        IERC20 _usdt,
        address _referralContract,
        address _fundReceiver,
        address _defaultRef,
        uint64 stage0StartTime
    ) Ownable(msg.sender) {
        if (
            address(_token) == address(0) ||
            address(_usdt) == address(0) ||
            _fundReceiver == address(0) ||
            _referralContract == address(0)
        ) revert ZeroAddress("Zero Address");
        token = _token;
        usdt = _usdt;
        fundReceiver = _fundReceiver;
        referralContract = _referralContract;
        DEFAULT_REFERRER = _defaultRef;

        uint64 start = stage0StartTime == 0
            ? uint64(block.timestamp)
            : stage0StartTime;

        stages[0] = Stage({
            tokensAvailable: 0,
            tokensAlloted: 0,
            tokensSold: 0,
            startTime: start,
            duration: uint32(9 days),
            price: uint256(3e14), // 0.0003 * 1e18 = 3e14
            minAmount: 5000 * 1e18,
            maxAmount: 10000000 * 1e18
        });
        stages[1] = Stage({
            tokensAvailable: 0,
            tokensAlloted: 0,
            tokensSold: 0,
            startTime: 0,
            duration: uint32(9 days),
            price: uint256(5e14), // 0.0005 * 1e18
            minAmount: 5000 * 1e18,
            maxAmount: 10000000 * 1e18
        });
        stages[2] = Stage({
            tokensAvailable: 0,
            tokensAlloted: 0,
            tokensSold: 0,
            startTime: 0,
            duration: uint32(9 days),
            price: uint256(7e14), // 0.0007 * 1e18
            minAmount: 5000 * 1e18,
            maxAmount: 10000000 * 1e18
        });
    }

    // ============ ADMIN ============

    // migration
    function adminBatchMigrateStage0_Replace(
        address[] calldata users,
        uint256[] calldata referralAmounts,
        uint256[] calldata totalPurchasedArr,
        uint256[] calldata purchasesCounts,
        uint256[] calldata purchasesAmounts,
        uint64[] calldata purchasesTimestamps
    ) external onlyOwner {
        require(!isMigrated, "Already Migrated");
        uint256 N = users.length;
        require(referralAmounts.length == N, "referral len");
        require(totalPurchasedArr.length == N, "totalPurchased len");
        require(purchasesCounts.length == N, "purchasesCounts len");

        uint256 flatIdx = 0;
        for (uint256 i = 0; i < N; i++) {
            address user = users[i];

            // scalars
            referralEarnings[user] = referralAmounts[i];
            totalPurchased[user] = totalPurchasedArr[i];

            // only update stage 0 as requested
            totalPurchasedInStage[0][user] = totalPurchasedArr[i];

            // overwrite purchases: delete existing array then push new entries
            delete _purchases[user];

            uint256 cnt = purchasesCounts[i];
            for (uint256 j = 0; j < cnt; j++) {
                uint256 amount = purchasesAmounts[flatIdx];
                uint256 claimed = 0;
                uint64 ts = purchasesTimestamps[flatIdx];

                _purchases[user].push(
                    Purchase({amount: amount, claimed: claimed, timestamp: ts})
                );
                emit MigrationPurchaseAppended(
                    user,
                    _purchases[user].length - 1
                );
                flatIdx++;
            }
        }

        isMigrated = true;

        emit MigrationBatchReplaced(1, N);
    }

    function adminSetTotalTokensSold(uint256 _total) external onlyOwner {
        require(!isTotalMigrated, "Already Migrated");
        stages[currentStage].tokensAvailable -= _total;
        stages[currentStage].tokensSold += _total;
        totalTokensSold = _total;
        isTotalMigrated = true;
    }

    function addStageTokens(uint256 stageIndex, uint256 amount)
        external
        onlyOwner
    {
        if (stageIndex >= TOTAL_STAGES) revert BadStage("Wrong Stage");
        stages[stageIndex].tokensAlloted += amount;
        stages[stageIndex].tokensAvailable += amount;
        emit StageTokensAdded(stageIndex, amount);
    }

    function updateStageDuration(uint256 stageIndex, uint32 newDuration)
        external
        onlyOwner
    {
        if (stageIndex >= TOTAL_STAGES) revert BadStage("Wrong Stage");
        stages[stageIndex].duration = newDuration;
        emit StageDurationUpdated(stageIndex, newDuration);
    }

    function updateStage(
        uint256 stageIndex,
        uint64 _startTime,
        uint32 _duration,
        uint256 _price,
        uint256 _minAmt,
        uint256 _maxAmt
    ) external onlyOwner {
        stages[stageIndex].startTime = _startTime;
        stages[stageIndex].duration = _duration;
        stages[stageIndex].price = _price;
        stages[stageIndex].minAmount = _minAmt;
        stages[stageIndex].maxAmount = _maxAmt;

        emit StageUpdated(
            stageIndex,
            _startTime,
            _duration,
            _price,
            _minAmt,
            _maxAmt
        );
    }

    function updateFundReceiver(address newReceiver) external onlyOwner {
        if (newReceiver == address(0)) revert ZeroAddress("Zero Address");
        fundReceiver = newReceiver;
        emit FundReceiverUpdated(newReceiver);
    }

    function setReferralRate(
        uint16 _level1,
        uint16 _level2,
        uint16 _level3
    ) external onlyOwner {
        require(
            _level1 + _level2 + _level3 <= 10000,
            "Total referral rate exceeds 100%"
        );
        level1RefPercent = _level1;
        level2RefPercent = _level2;
        level3RefPercent = _level3;
    }

    function setInitialUnlockPercent(uint256 _newPercent) external onlyOwner {
        require(_newPercent <= 100, "Cannot exceed 100%");
        INITIAL_UNLOCK_PERCENT = _newPercent;
        emit InitialUnlockPercentUpdated(_newPercent);
    }

    function setLockPeriod(uint256 _newPeriod) external onlyOwner {
        require(_newPeriod <= 365 days, "Lock period too long");
        LOCK_PERIOD = _newPeriod;
        emit LockPeriodUpdated(_newPeriod);
    }

    function setVestingDuration(uint256 _newDuration) external onlyOwner {
        require(_newDuration >= 30 days, "Vesting too short");
        require(_newDuration <= 1825 days, "Vesting too long");
        VESTING_DURATION = _newDuration;
        emit VestingDurationUpdated(_newDuration);
    }

    function updateDefaultRef(address _ref) external onlyOwner {
        require(_ref != address(0), "Zero Address");
        DEFAULT_REFERRER = _ref;
    }

    function sendLeftoverToNextStage() external onlyOwner {
        checkStageAdvance();
    }

    function updateStagePrice(uint256 stageIndex, uint256 newPrice)
        external
        onlyOwner
    {
        require(stageIndex < TOTAL_STAGES, "Invalid stage");
        require(newPrice > 0, "Price must be positive");
        require(
            currentStage < stageIndex ||
                block.timestamp < stages[stageIndex].startTime,
            "Cannot update active or past stage"
        );

        stages[stageIndex].price = newPrice;
        emit StagePriceUpdated(stageIndex, newPrice);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function updateReferralContract(address _referralContract)
        external
        onlyOwner
    {
        require(_referralContract != address(0), "Invalid Address");
        referralContract = _referralContract;
    }

    // ============ BUY ============

    /// @notice Buy `amount(USDT)` for tokens (18 decimals). `ref` optional; first valid referrer is locked.
    function buyTokens(uint256 _usdtAmount)
        external
        nonReentrant
        whenNotPaused
    {
        // carry leftover to new stage when duration passed
        checkStageAdvance();

        uint256 cs = currentStage;
        Stage memory s = stages[cs];

        uint256 tokenAmount = (_usdtAmount * 1e18) / s.price;

        require(tokenAmount > 0, "Token amount too small");

        if (tokenAmount < s.minAmount) revert BelowMin("Minimum Required");

        if (s.startTime == 0 || block.timestamp < s.startTime)
            revert StageNotStarted("Stage Not Started");
        if (block.timestamp > (s.startTime) + (s.duration))
            revert StageEnded("Stage Ended");
        if (s.tokensAvailable < tokenAmount) revert InsufficientStageTokens();

        uint256 newTotal = totalPurchased[msg.sender] + (tokenAmount);
        uint256 totalInAStage = totalPurchasedInStage[cs][msg.sender] +
            tokenAmount;
        if (totalInAStage > s.maxAmount) revert ExceedsMax("Bought Max");

        // Update storage minimally
        stages[cs].tokensAvailable = s.tokensAvailable - tokenAmount;
        stages[cs].tokensSold += tokenAmount;
        totalTokensSold += tokenAmount;
        totalPurchased[msg.sender] = newTotal;
        totalPurchasedInStage[cs][msg.sender] = totalInAStage;
        _purchases[msg.sender].push(
            Purchase({
                amount: tokenAmount,
                claimed: 0,
                timestamp: uint64(block.timestamp)
            })
        );

        // lock referrer if first time
        address myRef = getMyref(msg.sender);

        // Pull USDT from buyer into THIS contract
        SafeTransfer.safeTransferFrom(
            usdt,
            msg.sender,
            address(this),
            _usdtAmount
        );

        // Referral instant payout in TOKEN
        address currentRef = myRef;
        uint256 refAmount;
        uint256 totalrefAmt = 0;

        for (uint256 level = 0; level <= 2; level++) {
            if (level == 0) {
                refAmount = (tokenAmount * level1RefPercent) / BASIS_POINTS;
            } else if (level == 1) {
                refAmount = (tokenAmount * level2RefPercent) / BASIS_POINTS;
            } else {
                refAmount = (tokenAmount * level3RefPercent) / BASIS_POINTS;
            }

            totalrefAmt += refAmount;

            address lockedRef = currentRef != address(0)
                ? currentRef
                : DEFAULT_REFERRER;

            if (refAmount > 0) {
                SafeTransfer.safeTransfer(token, lockedRef, refAmount);
                referralEarnings[lockedRef] += uint256(refAmount);
                emit ReferralPaid(lockedRef, msg.sender, refAmount);
            }

            currentRef = getMyref(currentRef);
        }

        require(totalrefAmt <= tokenAmount, "Referral exceeds payment");

        SafeTransfer.safeTransfer(usdt, fundReceiver, _usdtAmount);

        emit TokensPurchased(msg.sender, _usdtAmount, tokenAmount, cs);

        // If sold out early, start next stage immediately (if exists)
        if (stages[cs].tokensAvailable == 0 && cs < (TOTAL_STAGES - 1)) {
            _advanceStage(0);
        }
    }

    function getMyref(address user) internal view returns (address) {
        return IREFERRAL(referralContract).getMyReferer(user);
    }

    // ============ STAGE ADVANCE ============

    /// @notice Anyone may call to advance stage after time ends; leftover tokens carry to next stage.
    function checkStageAdvance() internal {
        uint256 cs = currentStage;
        if (cs >= TOTAL_STAGES - 1) return;

        Stage memory s = stages[cs];
        if (s.startTime == 0) return;
        if (block.timestamp <= uint256(s.startTime) + uint256(s.duration))
            return;

        uint256 leftover = stages[cs].tokensAvailable;
        _advanceStage(leftover);
    }

    function _advanceStage(uint256 carry) internal {
        uint256 cs = currentStage;
        if (cs >= TOTAL_STAGES - 1) return;

        if (carry > 0) {
            stages[cs].tokensAvailable = 0;
            stages[cs + 1].tokensAvailable += carry;
        }

        currentStage = cs + 1;
        stages[currentStage].startTime = uint64(block.timestamp);

        emit StageAdvanced(currentStage, block.timestamp, carry);
    }

    // ============ VESTING & CLAIMING ============

    function _vestedFor(Purchase memory p, uint256 ts)
        private
        view
        returns (uint256)
    {
        if (ts < uint256(p.timestamp) + LOCK_PERIOD) return 0;

        uint256 unlocked = (uint256(p.amount) * INITIAL_UNLOCK_PERCENT) /
            PERCENT_DENOMINATOR;
        uint256 remaining = uint256(p.amount) - unlocked;

        uint256 timePassed = ts - (uint256(p.timestamp) + LOCK_PERIOD);
        if (timePassed > VESTING_DURATION) timePassed = VESTING_DURATION;

        uint256 vestedLinear = (remaining * timePassed) / VESTING_DURATION;
        return unlocked + vestedLinear;
    }

    /// @notice Amount currently claimable (sale token units, 18 decimals)
    function claimableAmount(address user)
        public
        view
        returns (uint256 totalClaimable)
    {
        Purchase[] memory arr = _purchases[user];
        uint256 nowTs = block.timestamp;
        uint256 len = arr.length;
        for (uint256 i = 0; i < len; ) {
            uint256 vested = _vestedFor(arr[i], nowTs);
            if (vested > arr[i].claimed)
                totalClaimable += (vested - arr[i].claimed);
            unchecked {
                ++i;
            }
        }
    }

    function claimTokens() external nonReentrant {
        uint256 toClaim = claimableAmount(msg.sender);
        if (toClaim == 0) revert NothingToClaim("No Reward");
        if (token.balanceOf(address(this)) < toClaim)
            revert NotEnoughSaleTokens("Insufficient Balance");

        Purchase[] storage arr = _purchases[msg.sender];
        uint256 nowTs = block.timestamp;
        uint256 len = arr.length;
        for (uint256 i = 0; i < len; ) {
            uint256 vested = _vestedFor(arr[i], nowTs);
            if (vested > arr[i].claimed) {
                arr[i].claimed = uint256(vested);
            }
            unchecked {
                ++i;
            }
        }

        totalClaimed[msg.sender] += uint256(toClaim);
        SafeTransfer.safeTransfer(token, msg.sender, toClaim);
        emit TokensClaimed(msg.sender, toClaim);
    }

    // ============ VIEWS ============

    function userPurchasesCount(address user) external view returns (uint256) {
        return _purchases[user].length;
    }

    function userPurchaseAt(address user, uint256 idx)
        external
        view
        returns (Purchase memory)
    {
        return _purchases[user][idx];
    }

    function stageInfo(uint256 idx)
        external
        view
        returns (
            Stage memory s,
            bool isCurrent,
            uint256 endTime
        )
    {
        if (idx >= TOTAL_STAGES) revert BadStage("Wrong Stage");
        s = stages[idx];
        isCurrent = (idx == currentStage);
        endTime = s.startTime == 0
            ? 0
            : uint256(s.startTime) + uint256(s.duration);
    }

    /// @notice Preview cost in USDT wei (18 decimals) for given token `amount`.
    function tokenCostUSDT(uint256 tokenAmount)
        external
        view
        returns (uint256 usdtWei)
    {
        Stage memory s = stages[currentStage];
        usdtWei = (tokenAmount * s.price) / 1e18;
    }

    /// @notice Preview cost in USDT wei (18 decimals) for given token `amount`.
    function getTokenAmount(uint256 _usdtAmount)
        external
        view
        returns (uint256 tokenAmt)
    {
        Stage memory s = stages[currentStage];
        tokenAmt = (_usdtAmount * 1e18) / s.price;
    }

    // ============ SAFETY ============

    /// @notice Withdraw unsold sale tokens (owner)
    function emergencyWithdrawUnsoldTokens(uint256 amount) external onlyOwner {
        SafeTransfer.safeTransfer(token, owner(), amount);
    }

    /// @notice Recover other ERC20 tokens mistakenly sent
    function recoverERC20(IERC20 erc20, uint256 amount) external onlyOwner {
        SafeTransfer.safeTransfer(erc20, owner(), amount);
    }
}
